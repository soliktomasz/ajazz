# Ajazz Stream Dock (AKP03E) USB HID protocol

Reverse engineered from `Stream Dock AJAZZ.app` 3.10.197.1210 (`libSDLibrary.1.0.25.dylib`)
and confirmed against live USB traffic from an **Ajazz AKP03E**, firmware
`V3.AKP03E_PXL.02.010`.

Internally this device belongs to the Mirabox "N3" family; the vendor software
groups `AKP03`/`AKP03E`/`AKP03R` with `MBox-N3`.

## Device identity

| | |
|---|---|
| Vendor ID | `0x0300` |
| Product ID | `0x3002` |
| USB product string | `HOTSPOTEKUSB HID DEMO` |
| Manufacturer | `HOTSPOTEKUSB` |

Note the VID is a placeholder value, not a registered USB vendor ID, and the
product string is left over from a reference design. Match on VID+PID **and**
usage page.

## HID interfaces

The device exposes two interfaces on the same VID/PID:

| Usage page | Usage | Role | Input | Output |
|---|---|---|---|---|
| `0x0001` | `0x0006` | Boot keyboard (used when firmware emits keystrokes directly) | 8 B | 1 B |
| `0xFFA0` | `0x0001` | **Vendor control interface** | 512 B | 1024 B |

Everything below uses the vendor interface. Its report descriptor declares no
report IDs, so **report ID is 0**, input reports are 512 bytes and output
reports are **exactly 1024 bytes**. Pad every command with zeroes to 1024.

Report descriptor (54 bytes):

```
06 a0 ff  09 01  a1 01        Usage Page 0xFFA0, Usage 1, Application Collection
  09 02  a1 00                  Usage 2, Physical Collection
    06 a1 ff  09 03  09 04        Usage Page 0xFFA1, Usages 3 and 4
    15 80  25 7f  35 00  45 ff
    75 08  96 00 02  81 02        Report Size 8, Count 512  -> Input  (512 B)
    09 05  09 06
    15 80  25 7f  35 00  45 ff
    75 08  96 00 04  91 02        Report Size 8, Count 1024 -> Output (1024 B)
  c0 c0
```

## Command frame layout

```
byte  0..2   'C' 'R' 'T'          magic
byte  3..4   0x00 0x00
byte  5..    opcode, ASCII (3-5 bytes)
byte  ...    opcode-specific parameters
             remainder zero-filled to 1024 bytes
```

### Commands

| Opcode | Frame | Meaning |
|---|---|---|
| `DIS` | `CRT 00 00 "DIS"` | **Wake** the key screens. Must be first — the panel ignores artwork while asleep. |
| `HAN` | `CRT 00 00 "HAN"` | Put the key screens to sleep. |
| `LIG` | `CRT 00 00 "LIG" 00 00 <level>` | Backlight brightness at byte 10, 0–100. Vendor uses 90. |
| `QUCMD` | `CRT 00 00 "QUCMD" 11 11 00 11 00 11` | Startup command, bytes 10–15. The vendor issues this once before painting. |
| `CLE` | `CRT 00 00 "CLE" 00 00 00 <slot>` | Clear one slot (byte 11); `0xFF` clears all. |
| `BAT` | `CRT 00 00 "BAT" 00 00 <len_hi> <len_lo> <slot>` | Announce key artwork: 16-bit big-endian JPEG length at bytes 10–11, slot at byte 12. Raw JPEG follows as further 1024-byte output reports. |
| `STP` | `CRT 00 00 "STP"` | **Commit** pending image writes. Sent once after a batch of `BAT` uploads, not after each one. |
| `LOG` | `CRT 00 00 "LOG" <len 32-bit BE> 00` | Announce a full-panel background image; length is 32-bit big-endian at bytes 8–11. |
| `ULEND` | `CRT 00 00 "ULEND"` | End of a background/logo upload. |
| `CONNECT` | `CRT 00 00 "CONNECT"` | Heartbeat. The vendor sends it roughly every second to keep the session alive. |
| `MOD` | `CRT 00 00 "MOD" 00 00 <mode>` | Mode change, byte 10. |
| `SET` | `CRT 00 00 "SET" 00 00 <a> <b>` | Panel orientation / direction, bytes 10–11. |
| `VER` | `CRT 00 00 "VER"` | Firmware version request. **Present in the library but unused by the shipping software, and this firmware does not answer it** — read the version with a GET_REPORT instead (below). |

There is also a `CRT 00 00 "CLE" 00 00 "DC"` frame the vendor sends at shutdown.
It is a *clear* variant, so do not send it when you simply want to close the
handle — it blanks the panel.

`SDDevice::getFinishCommand` builds a `STP` variant with `'!'` at byte 9, but the
shipping software uses the plain `STP` for refreshes.

### Firmware version

The vendor software does **not** use a command for this. It issues a HID
GET_REPORT on the *input* report:

```
IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, reportID: 0, length: 21)
  -> "V3.AKP03E_PXL.02.010\0"
```

## Startup sequence

Exactly what the vendor software does, in order:

1. `IOHIDDeviceOpen` (no seize) and register an input-report callback (512-byte buffer)
2. GET_REPORT input, 21 bytes → firmware version string
3. `CRT 00 00 "DIS"` — wake
4. `CRT 00 00 "LIG" 00 00 5A` — brightness 90
5. `CRT 00 00 "QUCMD" 11 11 00 11 00 11`
6. `CRT 00 00 "LIG" 00 00 5A` — brightness again
7. `CRT 00 00 "CLE" 00 00 00 FF` — clear all slots
8. For each slot: `BAT` header, then the JPEG in 1024-byte output reports
9. `CRT 00 00 "STP"` — one commit for the whole batch
10. `CRT 00 00 "CONNECT"` periodically thereafter

There is **no `HAN` handshake** for this device family. `SDDevice::addHandshakePack`
builds a bare ASCII `"HAN"` frame (no `CRT` magic), but it is gated behind a
per-device capability flag and is not sent to the AKP03E. Sending it appears to
wedge the firmware: the panel freezes and stops reporting key events until the
device is power-cycled.

## Key artwork

* Format: **baseline JPEG**, JFIF, 3 components, 4:2:0 (`sampling 0x22,0x11,0x11`).
* Size: **64×64** for the six keys. The vendor also uploads slots 7–9 with slot 7
  at **140×140**; the AKP03E has no physical screens there, so those are
  presumably for a sibling model sharing the firmware.
* Slots are **1-based**.
* Artwork must be **rotated 270°** (i.e. the panel renders it turned 90°
  counter-clockwise) to appear upright on the AKP03E.
* Declared length in the `BAT` header is the exact JPEG byte count; the payload
  reports are zero-padded to the 1024-byte report size and the firmware uses the
  declared length to know where the image ends.

## Input reports

512 bytes, of which only the first eleven matter:

```
byte  0..2   'A' 'C' 'K'
byte  3..4   0x00 0x00
byte  5..6   'O' 'K'
byte  7..8   0x00 0x00
byte  9      control index
byte 10      state: 0x01 = pressed, 0x00 = released
```

### Control indices

The AKP03E has **twelve** controls. Every index below was established by
counted-press testing on hardware (press control A n times, B m times, and match
the counts), not inferred.

| Index | Control | State byte |
|---|---|---|
| `1`–`6` | LCD keys, `1 2 3` top row, `4 5 6` bottom row | `1` press, `0` release |
| `0x25` | Left screenless button | `1` press, `0` release |
| `0x30` | Middle screenless button | `1` press, `0` release |
| `0x31` | Right screenless button | `1` press, `0` release |
| `0x50` / `0x51` | **Large** encoder turn: CCW / CW | always `0` |
| `0x35` | **Large** encoder pressed inward | `1` press, `0` release |
| `0x90` / `0x91` | **Small-left** encoder turn: CCW / CW | always `0` |
| `0x33` | **Small-left** encoder pressed inward | `1` press, `0` release |
| `0x60` / `0x61` | **Small-right** encoder turn: CCW / CW | always `0` |
| `0x34` | **Small-right** encoder pressed inward | `1` press, `0` release |

Encoders emit one event per detent with state `0`; the **odd** index of each turn
pair is clockwise. The indices are deliberately *not* in ascending physical
order — the large encoder turns on `0x50/0x51` but presses on `0x35`, while the
small encoders turn on `0x90/0x91` and `0x60/0x61`. All three encoders click.

Physical layout: the six LCD keys form a 3x2 grid in the upper left, the three
screenless buttons sit in a row beneath them, the large encoder is upper right,
and the two small encoders sit below it.

No encoder-press events were observed, so the encoders on this unit appear not to
be clickable (or their presses are not reported on this interface).

The device does **not** acknowledge commands. The only input traffic is control
events, so there is no reply to use as a write-confirmation oracle.

## Profile and plugin formats

The vendor's on-disk formats closely follow Elgato's Stream Deck software:

* `.streamDockProfile` / `.sdProfile` are ZIP archives containing `manifest.json`
  plus an `Images/` directory. Actions are keyed by `"column,row"` strings with
  `UUID`, `Settings` and `States` fields.
* Plugins are `*.sdPlugin` bundles with a `manifest.json`, driven over a
  WebSocket with `registerPlugin`-style events, and run under a bundled Node
  runtime (`Contents/Helpers/node20`).

## Gotchas

* `IOHIDDeviceSetReport` returns `kIOReturnSuccess` on this device for *anything* —
  oversize reports, undersize reports, even feature reports on an interface that
  declares zero-length feature reports. **The return code proves nothing**; verify
  by observing the panel.
* Sending malformed frames (a bare `"HAN"`, or reports of the wrong length) can
  wedge the firmware. Symptoms: frozen panel, no key events. Unplug and replug to
  recover.
* Closing the HID handle does not clear the panel; the device retains the last
  committed images. Only `CLE` (or the shutdown `CLE ... "DC"` frame) clears them.
