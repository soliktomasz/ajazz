#!/usr/bin/env python3
"""Normalize SDDevice packet builders into payload templates.

For each builder we walk the arm64 disassembly in program order and record every
`strb` into the packet buffer, resolving the stored register back to either an
immediate, a shifted parameter, or a named parameter register. Builders that
write the HID report-ID into byte 0 are normalized so offsets are stated in
*payload* space (i.e. 'C' of "CRT" is offset 0).
"""
import re, subprocess

DY = "/Applications/Stream Dock AJAZZ.app/Contents/MacOS/libSDLibrary.1.0.25.dylib"
FUNCS = ["addHandshakePack","addHeartbeatPack","addAdjustBrightnessPack","getClearCommand",
         "getClearAllCommand","getFinishCommand","getUploadFinishedCommand","sendPicSizeCommand",
         "sendLogoSizeCommand","addModeChangedCommand","getQUCMDCommand","sendDisconnectCommand",
         "sendChangeDirectionCommand","sendSettingsPackHead","sendGIFToJPGInfo",
         "getSecondaryScreenPicInfo","addScreenOffPack","addWakeUpScreenPack"]

argv = ["lldb","-b","-o",f'target create --arch arm64 "{DY}"']
for f in FUNCS: argv += ["-o", f"disassemble --name SDDevice::{f}"]
out = subprocess.run(argv, capture_output=True, text=True).stdout

blocks, cur, name = {}, [], None
for line in out.splitlines():
    m = re.match(r".*`SDDevice::(\w+):\s*$", line)
    if m:
        if name: blocks[name] = cur
        name, cur = m.group(1), []; continue
    if name and re.search(r"<\+\d+>:", line): cur.append(line.strip())
if name: blocks[name] = cur

ARG = {"x1":"arg1","x2":"arg2","x3":"arg3","x4":"arg4","x5":"arg5","x6":"arg6"}

for f in FUNCS:
    lines = blocks.get(f)
    print(f"\n=== {f} ===")
    if not lines: print("  <not found>"); continue
    val, regmap, stores, reportid_at0 = {}, {}, [], False
    for ln in lines:
        # track argN aliasing:  mov x20, x1
        m = re.search(r"mov\s+(x\d+), (x[1-6])\b", ln)
        if m and m.group(2) in ARG:
            regmap[m.group(1)] = ARG[m.group(2)]
            val["w"+m.group(1)[1:]] = ARG[m.group(2)]
            continue
        m = re.search(r"ldrb\s+(w\d+), \[x0, #0xe8\]", ln)      # this->reportID
        if m: val[m.group(1)] = "REPORT_ID"; continue
        m = re.search(r"mov\s+(w\d+), #(-?0x[0-9a-f]+|-?\d+)", ln)
        if m: val[m.group(1)] = int(m.group(2),0) & 0xFF; continue
        m = re.search(r"lsr\s+(w\d+), (w\d+), #(\d+)", ln)
        if m:
            src = val.get(m.group(2), m.group(2))
            val[m.group(1)] = f"({src} >> {m.group(3)})"; continue
        m = re.search(r"strb\s+(w\d+|wzr), \[(x\d+)(?:, #(0x[0-9a-f]+|\d+))?\]", ln)
        if m:
            reg, off = m.group(1), int(m.group(3),0) if m.group(3) else 0
            v = 0 if reg == "wzr" else val.get(reg, f"<{reg}>")
            if off == 0 and v == "REPORT_ID": reportid_at0 = True
            stores.append((off, v))
    shift = 1 if reportid_at0 else 0
    seen = {}
    for off, v in stores:
        seen[off] = v                      # later store to same offset wins
    print(f"  report-ID byte prepended: {reportid_at0}  (offsets below are payload-relative)")
    for off in sorted(seen):
        if off == 0 and reportid_at0: continue
        v = seen[off]; p = off - shift
        if isinstance(v,int):
            ch = chr(v) if 32 <= v < 127 else '.'
            print(f"  payload[{p:3d}] = 0x{v:02x} '{ch}'")
        else:
            print(f"  payload[{p:3d}] = {v}")
    # ascii rendering of contiguous literal head
    head = ""
    for p in range(0, 24):
        v = seen.get(p + shift)
        head += chr(v) if isinstance(v,int) and 32 <= v < 127 else ("." if isinstance(v,int) else "*")
    print(f"  head: {head!r}")
