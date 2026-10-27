#!/usr/bin/env python3
"""Reconstruct packet templates from SDDevice builder functions.

Walks the arm64 disassembly of each builder, tracking `mov wN,#imm` into
registers and recording every `strb wN,[xB,#off]` byte store. The resulting
(offset -> byte) map is the literal part of the packet template.
"""
import re, subprocess, sys

DY = "/Applications/Stream Dock AJAZZ.app/Contents/MacOS/libSDLibrary.1.0.25.dylib"
FUNCS = [
    "addHandshakePack", "addHeartbeatPack", "addScreenOffPack", "addWakeUpScreenPack",
    "getClearCommand", "getClearAllCommand", "getFinishCommand", "getUploadFinishedCommand",
    "addAdjustBrightnessPack", "sendPicSizeCommand", "sendLogoSizeCommand",
    "addModeChangedCommand", "getQUCMDCommand", "sendDisconnectCommand",
    "sendChangeDirectionCommand", "sendSettingsPackHead", "sendGIFToJPGInfo",
    "sendSecondaryScreenPicInfo", "sendGetHardwareFirmwareVersion",
    "sendTransparentBackground", "getSecondaryScreenPicInfo",
]

cmds = [f'target create --arch arm64 "{DY}"']
for f in FUNCS:
    cmds.append(f"disassemble --name SDDevice::{f}")
argv = ["lldb", "-b"]
for c in cmds:
    argv += ["-o", c]
out = subprocess.run(argv, capture_output=True, text=True).stdout

# split into per-function blocks
blocks, cur, name = {}, [], None
for line in out.splitlines():
    m = re.match(r".*`SDDevice::(\w+):\s*$", line)
    if m:
        if name: blocks[name] = cur
        name, cur = m.group(1), []
        continue
    if name and re.search(r"<\+\d+>:", line):
        cur.append(line)
if name: blocks[name] = cur

MOV  = re.compile(r"<\+\d+>:\s+mov\s+(w\d+), #(0x[0-9a-f]+|-?\d+)")
STRB = re.compile(r"<\+\d+>:\s+strb\s+(w\d+|wzr), \[(x\d+)(?:, #(0x[0-9a-f]+|\d+))?\]")

for f in FUNCS:
    lines = blocks.get(f)
    print(f"\n=== SDDevice::{f} ===")
    if not lines:
        print("  <not found>"); continue
    regs, stores = {}, {}
    for ln in lines:
        m = MOV.search(ln)
        if m:
            regs[m.group(1)] = int(m.group(2), 0) & 0xFF
            continue
        m = STRB.search(ln)
        if m:
            reg, off = m.group(1), int(m.group(3), 0) if m.group(3) else 0
            val = 0 if reg == "wzr" else regs.get(reg)
            stores[off] = val
    if not stores:
        print("  (no literal byte stores; likely delegates or uses memcpy)")
    for off in sorted(stores):
        v = stores[off]
        if v is None:
            print(f"  [{off:3d}] = <runtime value>")
        else:
            ch = chr(v) if 32 <= v < 127 else '.'
            print(f"  [{off:3d}] = 0x{v:02x} '{ch}'")
    lit = "".join(chr(stores[o]) if stores.get(o) and 32 <= stores[o] < 127 else "?"
                  for o in sorted(stores))
    print(f"  ascii: {lit!r}   ({len(lines)} insns)")
