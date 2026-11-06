# The Mali-G52 on the A22: hardware and the panfrost service

The GPU is a **Mali-G52 MC2** (Bifrost), the same block as the Infinix Hot 20's (MT6768). It
needs no firmware; bringing it up is power, clocks and a reset, in MediaTek's order. The
driver is `kernel/bsd/dev/hakios.mali.c`, ported from the Infinix's `redwood_mali.c`.

| | |
| --- | --- |
| topckgen | `0x10000000` (the `mfg_sel` mux, main PLL's third, 364 MHz) |
| SPM | `0x10006000` (MFG_ASYNC, MFG, MFG_CORE0, MFG_CORE1 and their SRAMs; bus protection once MFG is up) |
| mfgcfg | `0x13000000` (BG3D clock gate) |
| Mali | `0x13040000` (GPU_ID, reset, L2, tiler, shader cores, address space 0, job slots) |

## The six steps

1. the `mfg_sel` mux in topckgen;
2. the four power domains in the SPM, and the bus protection released;
3. the block's own clock gate (`BG3D` in mfgcfg);
4. the GPU: which one it is, a soft reset, L2/tiler/two shader cores powered;
5. one small job (write a word) through address space 0 in identity mode, read back;
6. the same job again through the GPU's own page tables.

Boot-arg `mali=1`. The A22's run reached all six:

```
mali: GPU_ID 0x74021000 (Mali-G52 r1p0), shader cores 0x3, tiler 0x1, L2 0x1: all powered
mali: first job, identity mode ... the word 0xc0ffee01 -- the GPU ran it
mali: second job, through the GPU's page tables ... -- the GPU ran it
mali: came up to step 6 of 6
```

`kern.hakios.mali` reports the step; the GPU stays powered afterwards.

## What acceleration needs

The three layers are now in this tree:

- **panfrost IOKit service** — `kernel/iokit/Kernel/hakios.mali.cpp` speaks Linux's panfrost
  DRM interface (parameters, buffers, GPU addresses, job chains, waits, syncobjs) to the
  `RedwoodMali` service.
- **Mesa panfrost + a DRM shim** — `tools/mesa/hakios-drm` opens `RedwoodMali` when Mesa asks
  for `panfrost` and passes the DRM requests through as user-client calls. The Mesa patches in
  `tools/mesa/` add the Darwin mmap/BO handling; `tools/mk-mesa.sh` now builds
  `softpipe,panfrost` by default.
- **Metal for Mali** — the public common tree's `mtk` branch has the Mali Metal driver
  (`userland/src/metal`, `userland/src/redwoodmetal.m`) and the AIR→NIR→panfrost compiler
  (`tools/mesa/air/air_metal.c` built into `libOSMesa` by `panfrost-osmesa-air.patch`). It is
  now ported here: `libredwoodair.dylib` is a symlink to the panfrost `libOSMesa`, and the
  kernel already publishes `RedwoodMetal` / `RedwoodMetalDevice`. See `docs/metal-a22.md`.

So the remaining GPU work is not the kernel service any more: it is fixing the panfrost
blit/readback stalls seen on the A32 (the same Mali-G52), and running the now-buildable Metal
driver on the A22. The GL path is still the safe one for CoreAnimation until the Metal driver
and the missing QuartzCore `default.metallib` glue are checked on hardware.

## The panfrost service (test45)

`kernel/iokit/Kernel/hakios.mali.cpp` is the Infinix's `RedwoodMali.cpp` ported: an IOKit
service that speaks Linux's panfrost DRM interface (parameters, buffers, GPU addresses,
job chains, waits) and hands surfaces to/from MiniIOSurface. `MiniIOSurface` gained a
`maliSeq` and `MiniIOSurfaceDrawn()` waits on it, so the display never shows a surface the
Mali is still drawing.

With `mali=1` the kernel brings the GPU up and then starts it (test45):

```
mali: came up to step 6 of 6
RedwoodMali: the GPU is there for programs to draw with
```

So the path program → IOKit service → Mali is in place, and the client side is in
`tools/mesa/hakios-drm`: Mesa's panfrost opens the service as if it were `/dev/dri/renderD128`.
Build with `DRIVERS=softpipe,panfrost` (the default) and boot with `mali=1` (and `gl=1` for the
window server). If the GPU is absent or `OSMESA_SOFTWARE=1` is set, the same library falls back
to softpipe. The Metal driver and its build are described below and in `docs/metal-a22.md`.

## The user-space test

`tools/mali_job_test.c` opens the `RedwoodMali` service, asks for the GPU ID, makes a 4 KB
buffer, maps it, writes the same "store `0xc0ffee01`" job the kernel's bring-up uses, submits
it, waits and reads the word back. Its result goes to `kern.hakios.say`, which the kernel
repeats in its log once a minute.

Build it with the common tree's cross compiler and put it in the small image:

```sh
xnu-clang -arch arm64 -isysroot $THEOS/sdks/iPhoneOS16.5.sdk -O1 \
    -framework IOKit -framework CoreFoundation -o mali_job_test tools/mali_job_test.c
cd <common-tree>/userland
FLASHBOOT=1 EXTRA=/path/to/mali_job_test RC_JOBS=rc.jobs.malitest ./build.sh
```

Then pack the payload with the new `root.apfs` and flash only `boot` (the small image travels
there; `xnusys` is not touched). `tools/rc.jobs.malitest` is the job list.

Run on the phone (test46), with Android back afterwards:

```
RedwoodMali: a client opened the GPU
RedwoodMali: request 0x44, 16 bytes      (GET_PARAM)
RedwoodMali: request 0x42, 24 bytes      (CREATE_BO)
RedwoodMali: request 0x40, 40 bytes      (SUBMIT)
mali_job_test: GPU 7402:1000, gpu address 0x1000000, job 1, wait 0, word c0ffee01 -- THE GPU RAN IT
```

So the whole path program → IOKit service → Mali works, with the same job the kernel's
bring-up runs.



## Metal

The Mali Metal driver and the AIR→panfrost compiler now build here; the build, the files in
the images, the boot arguments and the CoreAnimation caveat are in
[`metal-a22.md`](metal-a22.md). The GL path above is still the safe one for CoreAnimation until
that driver has been run on the phone.
