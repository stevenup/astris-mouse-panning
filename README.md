# astris-mouse-panning

English | [简体中文](README.zh-CN.md)

Smooth, analog mouse camera panning for [Astris](https://github.com/V380-Ori/Astris.Binaries), a Nintendo Switch emulator for macOS.

Mouse-to-key tools such as [MacRMB](https://github.com/ikoshura/MacRMB) turn the camera by holding down I/J/K/L, so the right stick only ever receives full tilt in eight directions and the camera moves in jerky steps. astris-mouse-panning converts mouse velocity into analog right-stick input on a virtual controller, so the camera turns as smoothly as it does with a real gamepad.

> [!NOTE]
> This is an unofficial project and is not affiliated with Astris or V380-Ori. It does not include, redistribute, or modify any Astris files. Use it at your own risk.

## Features

- **Analog right stick**: mouse movement is filtered and mapped to continuous stick deflection, updated every display frame.
- **Keyboard keeps working**: Player 1's key bindings from Astris's input settings are forwarded to the virtual controller, and edits there take effect immediately.
- **Real controllers take priority**: when Astris connects a physical controller whose ID matches Player 1, the virtual controller steps aside and the mouse drives the physical controller's right stick. The virtual controller comes back when the physical one disconnects.
- **Fully reversible**: nothing inside `Astris.app` is modified. Only the instance launched with `run.sh` is injected; opening Astris the usual way gives you the stock app.
- **No extra permissions**: everything runs inside the Astris process, so no Accessibility or Input Monitoring permission is required.

## Requirements

- Apple Silicon Mac running macOS 15 or later
- Xcode Command Line Tools (`xcode-select --install`) for building
- Astris (tested with 1.0.32), installed at `/Applications/Astris.app` by default

## Quick start

```bash
git clone https://github.com/stevenup/astris-mouse-panning.git
cd astris-mouse-panning
./run.sh                       # builds on first run, then launches Astris with panning support
./run.sh "/path/to/game.xci"   # same, and opens the game once Astris is up
```

Quit Astris (⌘Q) before running `run.sh`; it will not start a second instance. Astris runs detached from the terminal, so closing the terminal does not affect the game.

In the game, press **⌥⌘M** to start panning: the cursor disappears and you hear "Tink". Press ⌥⌘M again to stop ("Pop").

After pulling updates, run `./build.sh` to rebuild.

## Controls

| Action | How |
|---|---|
| Toggle panning | ⌥⌘M while the game window is focused, or `notifyutil -p dev.astrismouse.toggle` |
| Force stop | `notifyutil -p dev.astrismouse.stop` |
| Automatic stop | Switching to another app, closing the game window, or stopping emulation |
| Write runtime state to the log | `notifyutil -p dev.astrismouse.probe` |
| Write key bindings to the log | `notifyutil -p dev.astrismouse.diag` |
| Follow the log | `tail -f ~/Library/Logs/AstrisMouse.log` |

## Configuration

Copy `config.env.example` to `config.env`, uncomment the lines you want to change, then relaunch with `./run.sh`. To try a value for a single launch, pass it inline, e.g. `ASTRIS_MOUSE_FULL_SPEED=300 ./run.sh`.

| Variable | Default | Description |
|---|---|---|
| `ASTRIS_MOUSE_FULL_SPEED` | `400` | Mouse speed in pt/s that maps to full stick tilt. Lower is more sensitive. |
| `ASTRIS_MOUSE_CURVE` | `1` | Response curve exponent. 1.5–2 gives finer control at low speeds. |
| `ASTRIS_MOUSE_SMOOTHING_MS` | `20` | Low-pass filter time constant. Higher is smoother but floatier. |
| `ASTRIS_MOUSE_WINDOW_MS` | `24` | Velocity estimation window. Use 24–32 for 125 Hz mice and 8–12 for 1000 Hz mice. |
| `ASTRIS_MOUSE_ANTI_DEADZONE` | `0.10` | Non-zero output starts at this magnitude. Match it to Astris's right-stick deadzone (0.1 by default) so small movements still register. |
| `ASTRIS_MOUSE_OUTPUT_DEADZONE` | `0.02` | Output below this magnitude is sent as zero to prevent drift. |
| `ASTRIS_MOUSE_INVERT_Y` | `0` | Invert the vertical axis. |
| `ASTRIS_MOUSE_TOGGLE` | `cmd+alt+m` | Toggle hotkey. Modifiers: `cmd`, `alt`, `ctrl`, `shift`. Keys: `a`–`z`, `0`–`9`, `f1`–`f15`, `space`, `tab`, `esc`, `return`, or a raw key code. |
| `ASTRIS_MOUSE_SOUND` | `1` | Play a sound when panning starts and stops. |
| `ASTRIS_MOUSE_CONTROLLER` | auto | Force a specific libryujinx controller handle. Rarely needed. |
| `ASTRIS_MOUSE_DEBUG` | `0` | Log every input call from Astris and every value this tool sends. |

Options for `run.sh` and `build.sh`:

- `ASTRIS_APP=/path/to/Astris.app` if Astris is not in `/Applications`.
- `ASTRIS_MOUSE_FOREGROUND=1` to keep Astris attached to the terminal and stream the log live.

Key bindings are not configured here; they are read from Astris's own input settings.

## Troubleshooting

- **⌥⌘M does nothing**: the hotkey only works while Astris is the frontmost app, so click the game window first. `notifyutil -p dev.astrismouse.toggle` works regardless of focus.
- **Is the injection working?** The log should contain lines like:
  ```
  virtual gamepad "Pro Controller" connected as controller 0 (startup)
  Application ConfigureInputs: Configured Gamepad 'AstrisMouse' for Player1   ← when a game starts
  panning ON (...) controller=0 virtual window="..."                         ← after ⌥⌘M
  ```
- **Vertical look is inverted**: set `ASTRIS_MOUSE_INVERT_Y=1`.
- **The build cannot find `libryujinx.dylib`**: point `ASTRIS_APP` at your `Astris.app`.
- **Anything else**: launch with `ASTRIS_MOUSE_DEBUG=1 ./run.sh`, reproduce the problem, and attach `~/Library/Logs/AstrisMouse.log` to an issue.

## Uninstall

- **Back to stock Astris**: quit Astris and open it the usual way (Dock, Finder, or Spotlight). Nothing needs to be undone, because `Astris.app` is never modified.
- **Remove build output and logs**: quit Astris and run `./uninstall.sh`. Delete the folder to remove everything.

## How it works

1. `run.sh` starts Astris through `build/astris-launch`, which sets `DYLD_INSERT_LIBRARIES` only for the Astris process. Astris's code-signing entitlements (`com.apple.security.cs.allow-dyld-environment-variables` and `com.apple.security.cs.disable-library-validation`) allow this without re-signing.
2. `libAstrisMouse.dylib` uses dyld interposing to intercept Astris's calls into `libryujinx`: controller connect and disconnect, stick, button, keyboard, and `stop_emulation`.
3. It calls `ryujinx_connect_controller` with Player 1's `controllerId` (usually `Pro Controller`), so Player 1 binds to the virtual controller.
4. Once Player 1 is a gamepad, Astris stops mapping the keyboard to it, so the dylib reads Player 1's key bindings from Astris's preferences and forwards them to the virtual controller's sticks and buttons.
5. While panning is on, the cursor is hidden and decoupled from the mouse. On every display frame, recent mouse deltas are converted to a velocity, shaped by the response curve, low-pass filtered, offset past the deadzone, and written to the right stick with `ryujinx_set_controller_stick_axis`.

## Development

### Project layout

| Path | Purpose |
|---|---|
| `Sources/AstrisMouse.swift` | Virtual controller lifecycle, keyboard forwarding, mouse sampling and filtering, hotkey, Darwin notifications |
| `Sources/interpose.c` | dyld interpose table for the libryujinx calls |
| `Sources/launcher.c` | `astris-launch`, which starts Astris in its own session and injects the dylib into it only |
| `Sources/bridge.h`, `Sources/callbacks.h` | libryujinx C API declarations and C-to-Swift hooks |
| `build.sh`, `run.sh`, `uninstall.sh` | Build, launch, and clean up |
| `config.env.example` | Configuration template |

### libryujinx C API notes

These signatures were recovered by disassembling Astris 1.0.32 (arm64) and may differ in other versions.

- `int32 ryujinx_connect_controller(const char *id, const char *name)`: returns the slot handle, or -1 if the ID already exists or there is no input manager.
- `void ryujinx_disconnect_controller(const char *id)`
- `void ryujinx_set_controller_stick_axis(int32 controller, int32 stick, float x, float y)`: stick 0 is left and 1 is right; positive y is up; values range from -1 to 1.
- `void ryujinx_set_controller_button_pressed(int32 controller, int32 button, int32 pressed)`: buttons 0–16 are A, B, X, Y, Minus, Home, Plus, LStick, RStick, L, R, DpadUp, DpadDown, DpadLeft, DpadRight, ZL, ZR.
- `void ryujinx_set_keyboard_key_pressed(int32 macKeyCode, int32 pressed)`
- `ryujinx_start_emulation(const char *path)` / `ryujinx_stop_emulation(void)`

## License

[MIT](LICENSE)
