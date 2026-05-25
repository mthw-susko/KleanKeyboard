# KleanKeyboard

A tiny macOS app that **temporarily disables your keyboard and trackpad** so you
can wipe them down without typing gibberish or clicking things.

## How it works

When you start a cleaning session, the app installs a [`CGEventTap`](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate)
that swallows every keyboard, mouse, trackpad and gesture event. A full-screen
overlay shows a countdown so you know it's active.

To re-enable input you have two options (this mirrors how the popular
[KeyboardCleanTool](https://folivora.ai/keyboardcleantool) works):

- **Press `Esc`** — caught by the app and never passed through to other apps.
- **Wait for the countdown** — input re-enables automatically (10s–5min, your choice).

Because both the keyboard and trackpad are disabled, `Esc` is the deliberate
unlock key: it's a single, easy-to-find key and the app intercepts it directly.

## Building

You need a Mac with the Xcode command-line tools (`xcode-select --install`).
A full Xcode install is not required.

```sh
./build_app.sh          # produces ./KleanKeyboard.app
./build_app.sh --run    # build and launch
```

You can also run it straight from the package during development:

```sh
swift run
```

## First launch: grant Accessibility permission

Disabling input requires Accessibility access. On first launch the app will
prompt you. Open **System Settings ▸ Privacy & Security ▸ Accessibility**,
enable **KleanKeyboard**, then start a session.

The build script ad-hoc signs the bundle so the permission grant sticks across
rebuilds.

## Usage

1. Launch KleanKeyboard.
2. Pick how long the session should last (auto re-enable safety net).
3. Click **Start Cleaning**. The screen dims and input is disabled.
4. Clean your keyboard and trackpad.
5. Press **`Esc`** when done (or let the timer run out).

## App icon

A cute pastel keyboard mascot. The icon assets live in `icon/AppIcon.iconset/`
and `build_app.sh` compiles them into `AppIcon.icns` at build time. To tweak the
design, edit `icon/make_icon.py` (needs `pip install Pillow`) and re-run it:

```sh
python3 icon/make_icon.py
```

## Notes & limitations

- The hardware power button and Touch ID cannot be intercepted by software, so
  they always work — a useful escape hatch.
- Some security software that watches for input-tap programs may interfere.
- macOS may briefly disable the event tap under heavy load; the app
  automatically re-enables it.
