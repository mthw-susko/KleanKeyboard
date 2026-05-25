import AppKit
import ApplicationServices
import CoreGraphics

// Escape key (virtual keycode) used as the unlock key while input is disabled.
private let kEscapeKeyCode: Int64 = 53

// MARK: - Event tap that swallows keyboard + trackpad/mouse input

final class InputBlocker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called on the main thread when the user presses Esc while blocking.
    var onUnlockRequested: (() -> Void)?

    var isBlocking: Bool { eventTap != nil }

    /// Mask covering keyboard, mouse, trackpad and gesture event types.
    private static func eventMask() -> CGEventMask {
        var mask: CGEventMask = 0
        // Raw CGEventType values 1...34 cover mouse (1-7, 22-27), keyboard
        // (10-12) and trackpad gesture events (19-20, 29-34). null (0) and the
        // tap-disabled sentinels (0xFFFFFFFE/F) are intentionally excluded.
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

        // Esc unlocks. We detect it here and swallow it so it never reaches the
        // system (no stray Esc lands in whatever app was focused).
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == kEscapeKeyCode {
                DispatchQueue.main.async { [weak self] in
                    self?.onUnlockRequested?()
                }
                return nil
            }
        }

        // Everything else (all keys, clicks, movement, scroll, gestures) is dropped.
        return nil
    }
}

// MARK: - Full-screen overlay shown while input is disabled

final class OverlayController {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []

    func show(remainingText: String) {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.9)
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let container = NSView(frame: screen.frame)

            let title = makeLabel(
                "Keyboard & Trackpad Disabled",
                size: 38,
                weight: .bold,
                color: .white
            )
            let countdown = makeLabel(remainingText, size: 64, weight: .semibold, color: .white)
            let hint = makeLabel(
                "Wipe away! Press  Esc  to re-enable.",
                size: 22,
                weight: .regular,
                color: NSColor.white.withAlphaComponent(0.7)
            )

            let stack = NSStackView(views: [title, countdown, hint])
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
            window.orderFrontRegardless()

            windows.append(window)
            countdownLabels.append(countdown)
        }
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
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
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
        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 300)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KleanKeyboard"
        window.center()

        let root = NSView(frame: contentRect)

        let heading = NSTextField(labelWithString: "Clean Your Keyboard")
        heading.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        heading.alignment = .center

        let blurb = NSTextField(labelWithString:
            "Disables the keyboard and trackpad so you can wipe them down.\n" +
            "Press Esc at any time to re-enable.")
        blurb.font = NSFont.systemFont(ofSize: 13)
        blurb.textColor = .secondaryLabelColor
        blurb.alignment = .center
        blurb.maximumNumberOfLines = 0

        durationLabel = NSTextField(labelWithString: "")
        durationLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        durationLabel.alignment = .center

        durationSlider = NSSlider(value: 30, minValue: 10, maxValue: 300, target: self,
                                  action: #selector(durationChanged))
        durationSlider.numberOfTickMarks = 0
        durationSlider.translatesAutoresizingMaskIntoConstraints = false
        durationSlider.widthAnchor.constraint(equalToConstant: 320).isActive = true

        startButton = NSButton(title: "Start Cleaning", target: self,
                               action: #selector(startCleaning))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.controlSize = .large

        let stack = NSStackView(views: [heading, blurb, durationLabel, durationSlider, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20)
        ])

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        updateDurationLabel()
    }

    @objc private func durationChanged() {
        updateDurationLabel()
    }

    private func updateDurationLabel() {
        durationLabel.stringValue = "Auto re-enable after \(formatTime(Int(durationSlider.doubleValue)))"
    }

    // MARK: Cleaning session

    @objc private func startCleaning() {
        guard ensureAccessibilityPermission() else { return }

        guard blocker.start() else {
            presentError("Couldn't disable input. Make sure KleanKeyboard has " +
                         "Accessibility permission in System Settings.")
            return
        }

        remainingSeconds = Int(durationSlider.doubleValue)
        window.orderOut(nil)
        overlay.show(remainingText: formatTime(remainingSeconds))

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
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
