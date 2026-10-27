# AjazzDeck

A native macOS replacement for the **Stream Dock AJAZZ** software, for the
**Ajazz AKP03E** desk controller — 6 LCD keys, 3 plain buttons and 3 clickable
rotary encoders (12 controls in total).

No Qt, no bundled Chromium, no Node runtime — a ~1 MB menu-bar app plus a CLI,
talking directly to the device over IOKit HID.

The USB protocol was reverse engineered from the vendor software; see
[PROTOCOL.md](PROTOCOL.md) for the full write-up.

## Layout

| | |
|---|---|
| `Sources/AjazzKit` | The driver: HID transport, wire protocol, image encoding, config model, action runner |
| `Sources/ajazzdeck` | The app: menu-bar item plus the SwiftUI configuration window |
| `Sources/ajazzctl` | CLI for scripting and poking at the device |
| `re/` | Reverse-engineering tooling: the `hidspy` HID interposer and traffic captures |

## Build

```bash
./build-app.sh
```

That produces `build/AjazzDeck.app` and `.build/release/ajazzctl`.

```bash
open build/AjazzDeck.app
```

On first launch it writes a starter config, opens the configuration window, and
asks for **Accessibility** permission — required to synthesise keystrokes, media
keys, volume and scroll. Without it, controls that launch apps or open URLs still
work, but hotkey/media/volume actions silently do nothing.

Quit the vendor **Stream Dock AJAZZ.app** first; only one process can drive the
panel at a time.

> **If keystroke, media, volume, brightness or scroll actions stop working after
> you rebuild:** macOS ties Accessibility permission to the exact binary, and an
> ad-hoc signature changes on every build, so the existing entry goes stale while
> still *appearing* enabled. Remove **Ajazz Deck** from
> System Settings → Privacy & Security → Accessibility and add it again. The app
> detects this itself (via `CGPreflightPostEventAccess`) and shows a banner —
> opening apps, URLs and page switching keep working throughout, which is the
> tell-tale sign.

To start it at login: System Settings → General → Login Items → add `AjazzDeck.app`.

## The configuration window

Open it from the menu-bar icon → **Configure…**, or with ⌘, — closing it drops
the app back to a menu-bar-only utility.

* **Sidebar** — your pages, plus a Settings pane. Add, rename, duplicate and
  delete pages from the buttons at the bottom or the context menu.
* **Canvas** — a replica of the panel: the 3×2 key grid, the three plain buttons
  beneath it, and the large plus two small knobs on the right, laid out the way
  they sit on the desk. Click any control to edit it. Touching a control on the
  actual device lights it up here, which is a quick way to confirm a mapping.
  Drag a key onto another to swap them. ⌘C / ⌘X / ⌘V (or right-click) copy,
  cut and paste a control — across pages too, between controls of the same kind.
* **Inspector** — everything about the selected control: label, icon, colours,
  and its press / hold / turn actions.
* **Settings** — backlight, hold delay, Accessibility status, open-at-login,
  live device info (firmware, serial), *Import…* / *Export…*, and *Reset to
  Defaults*.

Every edit is applied to the panel and saved immediately; there is no Save
button.

## Configuration file

`~/.config/ajazzdeck/config.json`. The window writes it, and edits you make in a
text editor are picked up about a second after you save.

```json
{
  "brightness": 90,
  "longPressSeconds": 0.5,
  "pages": [
    {
      "name": "Main",
      "keys": {
        "1": {
          "label": "Finder",
          "color": "#0a84ff",
          "action": { "type": "launch", "value": "Finder" }
        },
        "2": {
          "icon": "/Users/me/Pictures/slack.png",
          "action": { "type": "url", "value": "https://slack.com" },
          "longPressAction": { "type": "shell", "value": "say hello" }
        }
      },
      "buttons": {
        "1": { "action": { "type": "media", "value": "previous" } }
      },
      "knobs": {
        "1": {
          "action": { "type": "volume" },
          "step": 1,
          "pressAction": { "type": "volume", "value": "mute" }
        },
        "2": { "action": { "type": "scroll" }, "step": 3 }
      }
    }
  ]
}
```

`idleMinutes` (optional) turns the key screens off after that many minutes
without input. The first touch afterwards only wakes the panel.

### Keys

Slots are `"1"`–`"6"`, matching the six screens.

| Field | Meaning |
|---|---|
| `label` | Text drawn on the key, auto-shrunk to fit |
| `icon` | Path to a PNG/JPEG/PDF, drawn aspect-fill. Takes precedence over label art |
| `symbol` | An icon drawn in `textColor`: an SF Symbol name (`"play.fill"`), or a Material Symbol as `"material:home"` / `"material-fill:home"`. *Choose…* in the inspector browses both sets. Loses to `icon` |
| `showTitle` | `false` hides `label` on the key (default `true`) |
| `titlePosition` | `top` / `middle` / `bottom`; default middle on a plain key, bottom over an icon or symbol |
| `titleSize` | label size in key pixels (keys are 64 px); omit to fit automatically |
| `live` | self-updating text in place of `label`: `{"source": "clock", "value": "HH:mm"}`; sources `clock`, `volume`, `audioOutput` (current output's name), `cpu`, `battery`, `shell` (value = command, first output line, every 5 s) |
| `toggle` | makes a toggle key: `{label, icon, symbol, color, textColor, action}` for the second state, each falling back to the first state's |
| `color` | Background `#rrggbb` (default black) |
| `textColor` | Label colour `#rrggbb` (default white) |
| `action` | Fired on release |
| `longPressAction` | Fired after `longPressSeconds`; suppresses the short action |

### Plain buttons

`buttons` is keyed `"1"`–`"3"`, left to right — the three screenless buttons
under the key grid. They take `action` and `longPressAction` only, since they
have nothing to display.

### Knobs

`knobs` is keyed `"1"`–`"3"` in physical order: `"1"` is the large knob,
`"2"` and `"3"` are the small ones. `action` handles rotation, `step` multiplies
each detent (default 1), and `pressAction` fires when the knob is clicked in.

### Per-app pages

A page's `apps` lists bundle identifiers, e.g. `["com.apple.Safari"]`. While one
of them is frontmost the panel shows that page; switching to an unlisted app
returns to the page you last picked by hand.

### Action types

| `type` | `value` | Notes |
|---|---|---|
| `launch` | app name, bundle id, or path | e.g. `"Safari"`, `"com.apple.Safari"` |
| `url` | any URL | opened with the default handler |
| `shell` | shell command | run via `/bin/sh -c` |
| `hotkey` | e.g. `"cmd+shift+4"` | modifiers: `cmd` `shift` `alt` `ctrl` `fn` |
| `media` | `playpause` / `next` / `previous` | |
| `volume` | `up` / `down` / `mute` | as a knob action, relative |
| `brightness` | `up` / `down` | display brightness; as a knob, relative |
| `deckBrightness` | — | the panel's own backlight; as a knob, relative |
| `scroll` | — | knob only, scrolls the focused view |
| `page` | `next` / `prev` / a page name | switch pages |
| `multi` | — | runs `steps` (a list of actions) in order |
| `delay` | seconds, e.g. `"0.5"` | inside `steps` only: pause before the next step |
| `task` | a task id, e.g. `macos.lockScreen` | a ready-made operation from a task group, below; settings go in `args` |
| `none` | — | decorative key |

### Tasks

Ready-made operations, organised in groups; each group is a submenu of the
inspector's action menu. Groups live in `Sources/AjazzKit/TaskLibrary.swift` —
adding one there is all it takes to make it appear in the app.

**macOS** — presses: `macos.lockScreen` Lock Screen, `macos.sleepDisplay` Sleep Display, `macos.sleep` Sleep, `macos.screenSaver` Start Screen Saver, `macos.missionControl` Mission Control, `macos.appWindows` App Windows, `macos.showDesktop` Show Desktop, `macos.spotlight` Spotlight, `macos.screenshot` Screenshot…, `macos.emoji` Emoji & Symbols, `macos.forceQuit` Force Quit…, `macos.darkMode` Toggle Dark Mode, `macos.minimize` Minimize Window, `macos.fullScreen` Toggle Full Screen, `macos.hideApp` Hide App, `macos.ejectAll` Eject All Disks.
Knob turns: `macos.spaces` Switch Desktops, `macos.tabs` Switch Tabs, `macos.zoom` Zoom In / Out, `macos.undoRedo` Undo / Redo.
Mission Control, App Windows, Show Desktop and Switch Desktops send the default
shortcuts from System Settings ▸ Keyboard ▸ Keyboard Shortcuts.

**Audio** — `audio.toggleOutput` Toggle Output (each press switches between two
outputs you pick), `audio.setOutput` Switch to Output, and on a knob
`audio.cycleOutputs` Cycle Outputs. Outputs are stored by device UID in `args`,
e.g. `{"type": "task", "value": "audio.toggleOutput", "args": ["BuiltInSpeakerDevice", "<headphones UID>"]}`;
the inspector picks them from a list, so you never need to type one.

## CLI

```bash
ajazzctl info                  # HID interfaces and identity
ajazzctl version               # firmware version
ajazzctl listen                # print key and knob events
ajazzctl bright 60             # backlight
ajazzctl label 1 "Build"       # render text onto a key
ajazzctl image 2 icon.png      # upload artwork
ajazzctl solid 3 '#ff0000'     # fill a key
ajazzctl clear all             # blank every key
ajazzctl calibrate             # label each slot with its index
ajazzctl wake | ajazzctl sleep # screens on / off
ajazzctl raw 4352540000...     # send a raw frame
```

`--size <px>` and `--rot <none|90|180|270|fliph|flipv>` override the per-slot
defaults, which is how you'd adapt this to a different model in the family.

Stop `AjazzDeck.app` before using the CLI to paint keys, or the two will fight
over the panel. The app itself refuses to run twice for the same reason — a
second instance would open the same HID interface and both copies would react to
every control.

Set `AJAZZDECK_DEBUG=1` to trace event dispatch on stderr, which is the quickest
way to tell "the control is not reaching the app" from "the action is not firing":

```bash
AJAZZDECK_DEBUG=1 ./build/AjazzDeck.app/Contents/MacOS/AjazzDeck
```

## Supporting another model

`DeckProfile` in `Sources/AjazzKit/DeckProfile.swift` holds everything
model-specific: image slots and their bitmap sizes, the key grid shape, the
protocol index of every button and encoder, and the rotation needed for artwork
to look upright. The configuration window builds its canvas from that profile, so
a new model needs no UI changes. The AKP03E profile is the only verified one.

## Known limits

* Only the AKP03E is verified. Other Ajazz/Mirabox panels in the `MBox-N3`
  family very likely work with a new `DeckProfile`.
* The device retains the last committed images, so the panel keeps showing your
  layout after the app quits. That's the firmware's behaviour, not a bug.
* Malformed frames can wedge the firmware — the panel freezes and stops sending
  key events. Unplug and replug to recover. `AjazzKit` only sends frames verified
  against captured vendor traffic, so this shouldn't happen in normal use.
* Control indices are not in ascending physical order (the large knob turns on
  `0x50/0x51` but presses on `0x35`). They were established by counted-press
  testing on hardware and are recorded in `DeckProfile`.

## Credits

Material Symbols Rounded (`Resources/MaterialSymbols/`) is © Google, used under
the Apache License 2.0 (see the `LICENSE` file beside the font).
