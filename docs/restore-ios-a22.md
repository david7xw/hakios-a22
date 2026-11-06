# Restoring the iOS files and the system image

This repository never carries a file of Apple's. The iOS user space, the dyld shared cache, the
device-tree identity and the APFS system image are all made on the builder's machine from an
IPSW that the builder supplies. They live in directories that `.gitignore` keeps out of git, so
`git checkout`/`git clean` cannot bring them back:

| what | where | made by |
| --- | --- | --- |
| extracted iOS 16.5 userland | `sysimage/rootfs`, `sysimage/cryptex`, `sysimage/cryptex-app`, `sysimage/20F66__iPhone10,3_6` | `sysimage/unpack.sh` |
| device-tree identity | `xnuloader/identity.h` | `xnuloader/mkidentity.sh` |
| kernel build tools and SDK | `xnu-deps/` | `xnu-deps/setup.sh` |
| system image for the `xnusys` partition | `userland/system.apfs` (about 2.5 GB) | `userland/build.sh` |
| the loader's smaller boot volume | `userland/root.apfs` | `userland/build.sh` |

The two directories that were deleted can be restored from the common HakiOS repository, which
is public:

```sh
git clone --depth 1 https://github.com/oosexgang/hakios-xnu-kernel.git
cp -a hakios-xnu-kernel/sysimage  <this-repo>/sysimage
cp -a hakios-xnu-kernel/xnu-deps  <this-repo>/xnu-deps
```

That restores the **scripts**, not the Apple files. `xnu-deps/setup.sh` then fetches the open
sources and host tools it needs. The rest of this page is the part that needs the IPSW.

## The IPSW this tree is built for

The user space and the identity are pinned to **iOS 16.5, build 20F66, for iPhone10,3/10,6
(iPhone X)**. The unpack script checks the size, because a different build would unpack and then
fail somewhere less obvious:

```
iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
6 165 698 198 bytes
```

Apple's CDN still serves it (the file is not signed for installation, but it downloads and
unpacks fine):

```
https://updates.cdn-apple.com/2023SpringFCS/fullrestores/032-85130/6AB0D10A-8AF9-4F6C-8CF5-A1B315CABE88/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
```

Put it in `downloads/` (ignored by git) and check the size:

```sh
mkdir -p downloads
curl -L --continue-at - -o downloads/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw \
  https://updates.cdn-apple.com/2023SpringFCS/fullrestores/032-85130/6AB0D10A-8AF9-4F6C-8CF5-A1B315CABE88/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
wc -c downloads/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw   # 6165698198
```

## Unpack it

Requirements: `python3`, `7z` 23 or newer (it must read APFS), `cc`, about 8 GB of free disk
while it runs and 5.3 GB afterwards.

```sh
cd <this-repo>
sysimage/unpack.sh downloads/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
```

It writes `sysimage/rootfs`, `sysimage/cryptex`, `sysimage/cryptex-app`,
`sysimage/20F66__iPhone10,3_6` and `sysimage/DeviceTree.d22ap.im4p`, and leaves `.done-*`
markers so a second run does not read the IPSW again. `KEEP=1` keeps the intermediate disk
images (`rootfs.dmg`, `cryptex-os.dmg`), which are needed only if `select-system.py` changes.

The same step through `make`:

```sh
make unpack IPSW=downloads/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
```

## Make the identity header

```sh
xnuloader/mkidentity.sh
# or: xnuloader/mkidentity.sh downloads/iPhone10,3,iPhone10,6_16.5_20F66_Restore.ipsw
```

This reads `Firmware/all_flash/DeviceTree.d22ap.im4p` out of the IPSW, decodes its LZFSE
payload and writes `xnuloader/identity.h`. Without it the loader can only be built with
`--placeholder`, which is enough for QEMU and an Apple-free user space, not for Darwin.

If no LZFSE decoder is installed, the script builds the BSD `lzfse` into
`xnu-deps/host/bin/lzfse`. On Linux, `apt install lzfse` (or the build fallback) is enough;
the fallback runs `make` in the cloned lzfse tree (older versions of the script asked for a
`lzfse` target that recent lzfse no longer has, and failed with "No rule to make target").

## Build the system image

The kernel and user space expect to be built from the common tree; this repository is the
A22 layer on top of it. The common tree also supplies files this repository does not track,
notably `Makefile`, `xnu-env.sh`, `tools/apfs`, and `userland/var`; building from this
repository alone will miss them. A reliable layout is a fresh common checkout with this
repository's files copied over it:

```sh
git clone --depth 1 https://github.com/oosexgang/hakios-xnu-kernel.git hakios
rsync -a <this-repo>/ hakios/
cd hakios
xnu-deps/setup.sh                 # host tools, SDK, open-source dependencies
make images                       # root.apfs + system.apfs (needs sysimage/)
make kernel                       # applies the XNU patch and builds hakios-kernel
make loader                       # builds xnuloader with identity.h
```

`xnu-deps/setup.sh` needs `git curl tar xz make cc clang flex bison m4 perl python3
autoconf automake` and a theos install with the Linux cctools and `iPhoneOS16.5.sdk`
(`$THEOS`, default `~/theos`).

`make images` is the long step: it writes `userland/system.apfs`, the 2.5 GB root filesystem
that goes into the `xnusys` partition, and `userland/root.apfs`, the small boot volume that
travels in `boot`. It takes the iOS files from `sysimage/`, so it cannot run before the IPSW
has been unpacked. `GL=1 make images` also builds Mesa (the panfrost driver by default), which
needs `meson`, `ninja`, `bison`, `flex`, and a working `python3 -m venv` (the `python3-venv`
package on Ubuntu); `tools/mk-mesa.sh` keeps its Python packages in
`xnu-deps/build/mesa/venv`.

## Put it on the phone

Flash **only** what changed. The A22 is legacy non-A/B: the boot partition is `boot`, there is
no `boot_a`/`boot_b`.

- Changed kernel, loader or boot volume: rebuild the chained `boot` image with
  `tools/chainboot.py` and flash `boot` only.
- Changed iOS user space: write `userland/system.apfs` to the `xnusys` partition (see the
  common tree's phone instructions) and leave `boot` alone if it did not change.
- Nothing is permanent: the loader starts XNU only when Android asks for it, and a run ends
  back in Android.

The `xnusys` partition itself is not recreated by any of this. If it was wiped, recreate it
with the common tree's `tools/gpt-carve.py`/phone procedure before writing `system.apfs`.

## Checks

```sh
ls sysimage/rootfs/System/Library/CoreServices      # unpacked userland
ls sysimage/20F66__iPhone10,3_6 | wc -l             # 43 cache files
test -s xnuloader/identity.h && grep -c device xnuloader/identity.h
ls -lh userland/system.apfs userland/root.apfs
```

If `sysimage/unpack.sh` says the IPSW size is wrong, it is a different build; either get the
20F66 file above or set `ANY_IPSW=1` and accept that later steps may fail.
