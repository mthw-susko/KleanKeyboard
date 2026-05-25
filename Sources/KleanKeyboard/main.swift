import AppKit
import ApplicationServices
import CoreGraphics

// Escape key (virtual keycode) used as the universal unlock key.
private let kEscapeKeyCode: Int64 = 53

private func isKeyboardEvent(_ type: CGEventType) -> Bool {
    switch type {
    case .keyDown, .keyUp, .flagsChanged:
        return true
    default:
        return false
    }
}

// MARK: - Event tap that selectively swallows keyboard and/or trackpad input

final class InputBlocker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Which device categories to suppress for the current session.
    var blockKeyboard = true
    var blockMouse = true

    /// When true, Esc unlocks regardless of which devices are blocked.
    var allowEscUnlock = true

    /// Called on the main thread when the user presses Esc while blocking.
    var onUnlockRequested: (() -> Void)?

    var isBlocking: Bool { eventTap != nil }

    /// Mask covering keyboard, mouse, trackpad and gesture event types. We tap
    /// everything and decide per-event what to drop, so a single tap serves all
    /// toggle combinations.
    private static func eventMask() -> CGEventMask {
        var mask: CGEventMask = 0
        // Raw CGEventType values 1...34 cover mouse (1-7, 22-27), keyboard
        // (10-12) and trackpad gesture events (19-20, 29-34). null (0) and the
        // tap-disabled sentinels are intentionally excluded.
        for raw in 1...34 {
            mask |= (CGEventMask(1) << raw)
        }
        return mask
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<InputBlocker>.fromOpaque(refcon).takeUnretainedValue()
            return blocker.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // .defaultTap lets us suppress events by returning nil
            eventsOfInterest: InputBlocker.eventMask(),
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system may disable the tap if our callback is too slow or after a
        // timeout. Re-enable it and let the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Esc unlocks (unless the user turned that off). We swallow it so a stray
        // Esc never lands in whatever app was focused.
        if allowEscUnlock, type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == kEscapeKeyCode {
                DispatchQueue.main.async { [weak self] in
                    self?.onUnlockRequested?()
                }
                return nil
            }
        }

        let shouldDrop = isKeyboardEvent(type) ? blockKeyboard : blockMouse
        return shouldDrop ? nil : Unmanaged.passUnretained(event)
    }
}

// MARK: - Overlay window that can become key (so its Stop button is clickable)

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Full-screen overlay shown while input is disabled

final class OverlayController {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var onStop: (() -> Void)?

    func show(
        title: String,
        hint: String,
        countdownText: String?,
        showStopButton: Bool,
        onStop: @escaping () -> Void
    ) {
        guard windows.isEmpty else { return }
        self.onStop = onStop
        let mainScreen = NSScreen.main ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.9)
            window.isOpaque = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let container = NSView(frame: screen.frame)
            var views: [NSView] = []

            views.append(makeLabel(title, size: 38, weight: .bold, color: .white))

            if let countdownText = countdownText {
                let countdown = makeLabel(countdownText, size: 64, weight: .semibold, color: .white)
                views.append(countdown)
                countdownLabels.append(countdown)
            }

            views.append(makeLabel(
                hint, size: 22, weight: .regular,
                color: NSColor.white.withAlphaComponent(0.7)
            ))

            // The clickable Stop button only goes on the main screen.
            if showStopButton && screen == mainScreen {
                let stop = NSButton(title: "Stop & Re-enable", target: self,
                                    action: #selector(stopTapped))
                stop.bezelStyle = .rounded
                stop.controlSize = .large
                stop.font = NSFont.systemFont(ofSize: 20, weight: .medium)
                views.append(stop)
            }

            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 24
            stack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])

            window.contentView = container
            if showStopButton && screen == mainScreen {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }

            windows.append(window)
        }
    }

    @objc private func stopTapped() {
        onStop?()
    }

    func updateCountdown(_ text: String) {
        for label in countdownLabels {
            label.stringValue = text
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        countdownLabels.removeAll()
        onStop = nil
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        return label
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = InputBlocker()
    private let overlay = OverlayController()

    private var window: NSWindow!
    private var blurb: NSTextField!
    private var keyboardCheck: NSButton!
    private var trackpadCheck: NSButton!
    private var escCheck: NSButton!
    private var timerCheck: NSButton!
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var warningLabel: NSTextField!
    private var startButton: NSButton!

    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainWindow()
        blocker.onUnlockRequested = { [weak self] in
            self?.stopCleaning()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: UI

    private func buildMainWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 440, height: 380)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KleanKeyboard"
        window.center()

        let root = NSView(frame: contentRect)

        let heading = NSTextField(labelWithString: "Clean Your Mac")
        heading.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        heading.alignment = .center

        blurb = NSTextField(labelWithString: "")
        blurb.font = NSFont.systemFont(ofSize: 13)
        blurb.textColor = .secondaryLabelColor
        blurb.alignment = .center
        blurb.maximumNumberOfLines = 0

        keyboardCheck = NSButton(checkboxWithTitle: "Disable keyboard",
                                 target: self, action: #selector(optionsChanged))
        keyboardCheck.state = .on

        trackpadCheck = NSButton(checkboxWithTitle: "Disable trackpad & mouse",
                                 target: self, action: #selector(optionsChanged))
        trackpadCheck.state = .on

        escCheck = NSButton(checkboxWithTitle: "Allow Esc to re-enable",
                            target: self, action: #selector(optionsChanged))
        escCheck.state = .on

        timerCheck = NSButton(checkboxWithTitle: "Auto re-enable after a time limit",
                              target: self, action: #selector(optionsChanged))
        timerCheck.state = .on

        durationLabel = NSTextField(labelWithString: "")
        durationLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        durationLabel.alignment = .center

        durationSlider = NSSlider(value: 30, minValue: 10, maxValue: 300, target: self,
                                  action: #selector(optionsChanged))
        durationSlider.translatesAutoresizingMaskIntoConstraints = false
        durationSlider.widthAnchor.constraint(equalToConstant: 340).isActive = true

        warningLabel = NSTextField(labelWithString: "")
        warningLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        warningLabel.textColor = .systemRed
        warningLabel.alignment = .center
        warningLabel.maximumNumberOfLines = 0

        startButton = NSButton(title: "Start Cleaning", target: self,
                               action: #selector(startCleaning))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.controlSize = .large

        let checks = NSStackView(views: [keyboardCheck, trackpadCheck, escCheck, timerCheck])
        checks.orientation = .vertical
        checks.alignment = .leading
        checks.spacing = 8

        let stack = NSStackView(views: [
            heading, blurb, checks, durationSlider, durationLabel, warningLabel, startButton
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24)
        ])

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        refreshControls()
    }

    @objc private func optionsChanged() {
        refreshControls()
    }

    private func refreshControls() {
        let timerOn = timerCheck.state == .on
        durationSlider.isEnabled = timerOn
        if timerOn {
            durationLabel.stringValue = "Re-enables after \(formatTime(Int(durationSlider.doubleValue)))"
            durationLabel.textColor = .labelColor
        } else {
            durationLabel.stringValue = "No time limit — stop with Esc or the Stop button"
            durationLabel.textColor = .secondaryLabelColor
        }
        let deviceSelected = keyboardCheck.state == .on || trackpadCheck.state == .on

        // Available stop mechanisms: Esc, the timer, or the Stop button (which
        // only works while the mouse stays enabled). At least one must exist or
        // there'd be no way out of a session.
        let mouseStaysEnabled = trackpadCheck.state == .off
        let escOn = escCheck.state == .on
        let canStop = escOn || timerOn || mouseStaysEnabled

        var ways: [String] = []
        if escOn { ways.append("press Esc") }
        if mouseStaysEnabled { ways.append("click Stop") }
        if ways.isEmpty {
            blurb.stringValue = "Pick what to disable. It re-enables when the timer ends."
        } else {
            blurb.stringValue = "Pick what to disable. To re-enable: "
                + ways.joined(separator: " or ") + "."
        }

        if deviceSelected && !canStop {
            warningLabel.stringValue =
                "No way to stop selected. Allow Esc, set a time limit, or keep the mouse enabled."
        } else {
            warningLabel.stringValue = ""
        }

        startButton.isEnabled = deviceSelected && canStop
    }

    // MARK: Cleaning session

    @objc private func startCleaning() {
        let blockKeyboard = keyboardCheck.state == .on
        let blockMouse = trackpadCheck.state == .on
        guard blockKeyboard || blockMouse else { return }
        guard ensureAccessibilityPermission() else { return }

        let allowEsc = escCheck.state == .on
        blocker.blockKeyboard = blockKeyboard
        blocker.blockMouse = blockMouse
        blocker.allowEscUnlock = allowEsc
        guard blocker.start() else {
            presentError("Couldn't disable input. Make sure KleanKeyboard has " +
                         "Accessibility permission in System Settings.")
            return
        }

        // The Stop button is only useful when the mouse still works.
        let showStopButton = !blockMouse
        let useTimer = timerCheck.state == .on

        var ways: [String] = []
        if allowEsc { ways.append("press Esc") }
        if showStopButton { ways.append("click Stop") }
        let hint: String
        if ways.isEmpty {
            hint = "Re-enables automatically when the timer ends."
        } else {
            hint = "To re-enable: " + ways.joined(separator: " or ") + "."
        }

        let countdownText: String?
        if useTimer {
            remainingSeconds = Int(durationSlider.doubleValue)
            countdownText = formatTime(remainingSeconds)
        } else {
            countdownText = nil
        }

        window.orderOut(nil)
        overlay.show(
            title: disabledTitle(keyboard: blockKeyboard, mouse: blockMouse),
            hint: hint,
            countdownText: countdownText,
            showStopButton: showStopButton,
            onStop: { [weak self] in self?.stopCleaning() }
        )

        if useTimer {
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
    }

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            stopCleaning()
        } else {
            overlay.updateCountdown(formatTime(remainingSeconds))
        }
    }

    private func stopCleaning() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        blocker.stop()
        overlay.hide()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Permissions / helpers

    private func disabledTitle(keyboard: Bool, mouse: Bool) -> String {
        switch (keyboard, mouse) {
        case (true, true):  return "Keyboard & Trackpad Disabled"
        case (true, false): return "Keyboard Disabled"
        case (false, true): return "Trackpad & Mouse Disabled"
        default:            return "Input Disabled"
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        // Stable documented value of kAXTrustedCheckOptionPrompt; used directly to
        // avoid the Unmanaged-vs-CFString import differences between SDK versions.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Needed"
        alert.informativeText =
            "KleanKeyboard needs Accessibility access to disable the keyboard and " +
            "trackpad.\n\nOpen System Settings ▸ Privacy & Security ▸ Accessibility, " +
            "enable KleanKeyboard, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "KleanKeyboard"
        alert.informativeText = message
        alert.runModal()
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
