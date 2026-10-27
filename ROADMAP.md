# AjazzDeck roadmap — parity with Stream Deck software

Baseline (2026-10-26): ~2,840 lines; all 12 AKP03E controls working; 7 action
types; SwiftUI configuration window. No tests, no sleep/wake handling, no per-app
switching, no idle dim.

Ordered by value per line. Tier 0 is the only part that is mandatory — the rest
is a menu.

## Recommended order

**1 → 2 → 4 → 6 → 5** — about two days. Survives sleep, won't silently regress,
switches with your app, has a real icon library, runs action sequences.

Do **#4 and #5 together**: both change the config schema, and doing them apart
means migrating `config.json` twice.

## Tier 0 — what "fully functional" means (~half a day)

- [x] **1. Sleep/wake reconnect** — `NSWorkspace.didWakeNotification` → reconnect
      and repaint. Today, closing the lid leaves the panel dead until relaunch.
      (~15 lines)
- [x] **2. Tests for `StreamDock.decode` and `StreamDockProtocol` frame builders**
      — pure functions, no device needed; a silent regression here bricks
      everything. (~60 lines)
- [x] **3. Idle dim / screen-off after N minutes** — device already speaks
      `CRT..HAN` / `CRT..DIS`. Stream Deck's "screensaver". (~20 lines)

## Tier 1 — features people use daily

- [x] **4. Per-app profile switching** — frontmost app → auto-select page.
      Highest leverage item on this list. (~25 lines + inspector picker)
- [x] **5. Multi-actions** — one key runs a list of actions with delays.
      (~40 lines + list editor)
- [x] **6. SF Symbols as key art** — `NSImage(systemSymbolName:)`; a free icon
      library with zero dependencies. (~20 lines)
- [x] **7. Title styling** — show/hide, position, size. (~20 lines)
- [x] **8. Toggle keys** — two states with alternating art. (~40 lines)
- [x] **9. Import/export profile** — config is already JSON; just open/save
      panels. (~20 lines)
- [x] **10. Drag-and-drop rearrange + copy/paste keys** on the canvas. (~half a
      day)

## Tier 2 — live keys (1–2 days)

- [x] **11.** One refresh timer plus a `displaySource` per key: clock, volume %,
      CPU, battery, now-playing, shell-command output. Covers most of why people
      install plugins, without a plugin system.
      Done without now-playing, which moved to #13 (MediaRemote is closed to
      third-party apps on current macOS; a `shell` key running osascript works meanwhile).

## Tier 3 — integrations (~1 day each)

- [ ] **12.** OBS via obs-websocket (scene switch, record/stream toggle, live state)
- [ ] **13.** Now-playing — MediaRemote or AppleScript
- [ ] **14.** Microphone mute via CoreAudio
- [ ] **15.** Focus modes / Do Not Disturb
- [ ] **16.** Window management

## Tier 4 — Elgato plugin ecosystem — recommended: skip

Running `.sdPlugin` bundles needs the full WebSocket event protocol, a WKWebView
host for property inspectors, a bundled Node runtime, and copes with plugins that
hardcode Elgato device IDs and key counts. Weeks of work; the vendor app needed
1.4 GB to do it. Tier 3 delivers the integrations you'd actually install for a
fraction of the effort. Only build this if you specifically want other people's
plugins.

This estimate comes from the shape of the vendor's bundle, not from a spike —
it could be worse.

## Tier 5 — distribution (only if sharing)

- [ ] **17.** Developer ID signing + notarization, DMG, Sparkle updates.
      A stable Developer ID signature also permanently fixes the Accessibility
      re-grant problem: TCC stops invalidating the permission on every rebuild.

## Notes

- All sizes assume the AKP03E profile. A second model needs its own on-hardware
  calibration pass (counted-press testing), as this one did — see `PROTOCOL.md`.
- Slots 7–9 have no physical screens on the AKP03E, so Stream Deck+ touch-strip
  features don't apply.
