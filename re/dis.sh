#!/bin/zsh
# dis.sh <mangled-symbol> — disassemble one function from libSDLibrary (arm64)
DY="/Applications/Stream Dock AJAZZ.app/Contents/MacOS/libSDLibrary.1.0.25.dylib"
SYM="$1"
nm -arch arm64 -n "$DY" 2>/dev/null | grep -E ' (T|t) ' | awk '{print $1, $3}' > /tmp/_syms.$$
START=$(grep -m1 " ${SYM}\$" /tmp/_syms.$$ | awk '{print $1}')
if [[ -z "$START" ]]; then echo "symbol not found: $SYM"; rm -f /tmp/_syms.$$; exit 1; fi
END=$(awk -v s="$START" '$1>s && seen==0 {print $1; seen=1}' /tmp/_syms.$$ | head -1)
rm -f /tmp/_syms.$$
echo "### $SYM  0x$START .. 0x$END"
objdump --macho --arch=arm64 -d --start-address=0x$START --stop-address=0x$END "$DY" 2>/dev/null | tail -n +4
