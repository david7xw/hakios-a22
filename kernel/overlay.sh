#!/bin/bash
# Put this repository's A22 kernel files over a common XNU tree prepared by xnu/apply.sh.
#
#   kernel/overlay.sh [XNU_TREE]       (default: XNU_SRC, else ../xnu-src/xnu-8796.121.2)
#
# The common tree's bsd/conf/files and iokit/conf/files are left alone: copying the old copies in
# this repository over them drops HFS/APFS and the common drivers. The A22 files that are not in
# the common drivers/ tree are appended after the common HakiOS block instead, where
# tools/hakios-config.py kernel (run by `make kernel`) leaves them alone.
set -e
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=${1:-${XNU_SRC:-$HERE/../xnu-src/xnu-8796.121.2}}

[ -d "$TREE" ] || { echo "overlay: no kernel tree at $TREE (run xnu/apply.sh first)" >&2; exit 1; }
grep -qF '# end of the HakiOS drivers' "$TREE/bsd/conf/files" ||
	{ echo "overlay: $TREE/bsd/conf/files has no HakiOS block (run xnu/apply.sh first)" >&2; exit 1; }

# Everything except the two generated/Apple conf/files copies.
(cd "$HERE/bsd" && tar -cf - --exclude='./conf/files' .) | (cd "$TREE/bsd" && tar -xf -)
(cd "$HERE/iokit" && tar -cf - --exclude='./conf/files' .) | (cd "$TREE/iokit" && tar -xf -)

# The drivers and IOKit files the common tree does not know about. `make kernel` rewrites the
# HakiOS block but never the lines after its end marker, so these stay.
append_once() {
	local file=$1 line=$2
	grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
for line in \
	'bsd/dev/hakios.fts.c                     standard' \
	'bsd/dev/hakios.mali.c                    standard' \
	'bsd/dev/hakios.mtkbattery.c              standard' \
	'bsd/dev/hakios.mtkcpufreq.c              standard' \
	'bsd/dev/hakios.mtkkeys.c                 standard' \
	'bsd/dev/hakios.scp.c                     standard'
do
	append_once "$TREE/bsd/conf/files" "$line"
done
append_once "$TREE/iokit/conf/files" 'iokit/Kernel/hakios.mali.cpp            optional iokitcpp'

# The copied files must look newer than drivers/ so xnu/sync-drivers.sh does not put the common
# (Qualcomm) versions back over them.
find "$TREE/bsd" "$TREE/iokit" -type f \
	\( -name 'hakios.*' -o -name 'MiniIOSurface.h' -o -name 'MiniIOMobileFramebuffer.cpp' \) \
	-exec touch {} +

if [ -f "$HERE/../tools/hakios-config.py" ]; then
	python3 "$HERE/../tools/hakios-config.py" kernel --tree "$TREE" >/dev/null
fi
echo "overlay: A22 kernel files installed in $TREE"
