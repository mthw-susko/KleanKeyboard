# KleanKeyboard

A tiny macOS app that **temporarily disables your keyboard and trackpad** so you
can wipe them down without typing gibberish or clicking things.

## How it works

When you start a cleaning session, the app installs a [`CGEventTap`](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate)
that swallows every keyboard, mouse, trackpad and gesture event. A full-screen
overlay shows a countdown so you know it's active.

You choose what to disable and how it re-enables:

**What to disable**
- **Keyboard** only,
- **Trackpad & mouse** only, or
- **both** (default).

**How to re-enable** (any of these, whichever applies)
- **Press `Esc`** — always works; caught by the app and never passed to other apps.
- **Click the Stop button** — shown in the overlay whenever the mouse stays
  enabled (i.e. "keyboard only" mode). This is the no-time-limit mouse mode:
  disable just the keyboard and click Stop when you're done.
- **Wait for the countdown** — optional auto re-enable (10s–5min). Turn it off
  for no time limit.

This mirrors how the popular [KeyboardCleanTool](https://folivora.ai/keyboardcleantool)
works (Esc to unlock), with selective toggles added.

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
2. Tick what you want to disable: **keyboard**, **trackpad & mouse**, or both.
3. Optionally enable **Auto re-enable** and pick a time limit (or leave it off
   for no time limit).
4. Click **Start Cleaning**. The screen dims and the chosen input is disabled.
5. Clean away, then re-enable by pressing **`Esc`**, clicking **Stop** (mouse
   mode), or letting the timer run out.

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
