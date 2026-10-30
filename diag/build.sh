#!/bin/bash
# Build a22diag.img: a22diag packed in front of Android's kernel in the A22's boot image.
#
#   ANDROID_BOOT=...  the stock/Magisk boot.img to chain to (no default: pass your own)
#
# Output: a22diag.bin (bare-metal) and a22diag.img (Android boot image v2, <= 32 MB).
# Both are generated and git ignores them.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [ ! -f "$HERE/font8x16.h" ]; then
    python3 "$ROOT/tools/mkfont8x16.py" > "$HERE/font8x16.h"
fi

if command -v clang >/dev/null 2>&1 && (command -v ld.lld >/dev/null 2>&1 || command -v zig >/dev/null 2>&1); then
    CC="${CC:-clang}"
    LLD="${LLD:-ld.lld}"
    command -v "$LLD" >/dev/null 2>&1 || LLD="zig ld.lld"
    CFLAGS="--target=aarch64-linux-gnu -ffreestanding -nostdlib -fno-builtin -fno-stack-protector -mgeneral-regs-only -mstrict-align -Os -Wall -Wextra -I$HERE"
    $CC $CFLAGS -c "$HERE/fbdiag_start.S" -o "$HERE/fbdiag_start.o"
    $CC $CFLAGS -c "$HERE/a22diag.c" -o "$HERE/a22diag.o"
    $LLD -T "$HERE/link.ld" --oformat binary "$HERE/fbdiag_start.o" "$HERE/a22diag.o" -o "$HERE/a22diag.bin"
else
    CC="${CC:-aarch64-linux-gnu-gcc}"
    LD="${LD:-aarch64-linux-gnu-ld}"
    OBJCOPY="${OBJCOPY:-aarch64-linux-gnu-objcopy}"
    CFLAGS="-ffreestanding -nostdlib -fno-builtin -fno-stack-protector -mgeneral-regs-only -mstrict-align -Os -Wall -Wextra -I$HERE"
    $CC $CFLAGS -c "$HERE/fbdiag_start.S" -o "$HERE/fbdiag_start.o"
    $CC $CFLAGS -c "$HERE/a22diag.c" -o "$HERE/a22diag.o"
    $LD -T "$HERE/link.ld" "$HERE/fbdiag_start.o" "$HERE/a22diag.o" -o "$HERE/a22diag.elf"
    $OBJCOPY -O binary "$HERE/a22diag.elf" "$HERE/a22diag.bin"
    rm -f "$HERE/a22diag.elf"
fi

BOOT="${ANDROID_BOOT:?build.sh: pass ANDROID_BOOT=/path/to/boot.img}"
[ -f "$BOOT" ] || { echo "build.sh: no boot image at $BOOT" >&2; exit 1; }
python3 "$ROOT/tools/chainboot.py" "$BOOT" "$HERE/a22diag.bin" "$HERE/a22diag.img"
ls -lh "$HERE/a22diag.bin" "$HERE/a22diag.img"
