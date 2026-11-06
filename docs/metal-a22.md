# Metal on the A22

The public `mtk` branch of the common tree is the A32-compatible Mali Metal work. The A22 port
takes its `userland/src/metal` (the command encoder, buffers, textures, render passes and the
`rwa_*` contract), `userland/src/redwoodmetal.m` (the `MTLDevice` and plug-in classes),
`metal_props`, `metal_drv_test` and the `rc.jobs.metal*` recipes. The compiler side is the same
branch's `tools/mesa/air` and `air_metal.c`, built into `libOSMesa` by
`panfrost-osmesa-air.patch`; `libredwoodair.dylib` is a symlink to that library. The
`panfrost-redwood-perf.patch` supplies the UBO/widening handling the driver expects.

Build (Mesa is rebuilt by `build.sh` with `AIR=1` the first time the patches or the AIR sources
change):

```sh
cd userland
GL=1 METAL=1 SYSTEM=1 ./build.sh
```

`SYSTEM=1` is needed once after the Metal files are added: the system image gets a symlink
`/System/Library/Extensions/RedwoodMetal.bundle -> /redwood/lib/RedwoodMetal.bundle`, created
from a copy of `system.manifest` by `build.sh` (the manifest itself is not modified). The root
image carries `lib/libredwoodair.dylib`, `lib/libredwoodmetal.dylib`,
`lib/RedwoodMetal.bundle`, and `bin/metal_props`, `bin/metal_drv_test`, `bin/say_run`,
`bin/tolog`, `bin/psgrep`.

Boot with `mali=1 gl=1 metal=1` (gl is still the safe window-server path), then run
`metal_props on` from a job or the console; `rc.jobs.metalprops` is the discovery sweep,
`rc.jobs.metalcompute` the first dispatch, and `rc.jobs.metaldraw` a draw using Apple's
`AppleMetalGLRenderer.bundle/default.metallib`, which this system image has. `metal_drv_test
--sweep` is the form that must be used while launchd is alive (it does not call `MTLAddDevice`).

Do **not** put `metal_plugin=1` in the default boot arguments yet. It publishes the properties
before launchd starts, so CoreAnimation may take Metal, and the A22 tree does not yet have the
A32's `inject.c` glue (`window_server_keeps_opengl_es`, `camtl=1`,
`give_quartzcore_its_shaders`). QuartzCore's `default.metallib` is also absent from the 20F66
root (only `default.pipelinelib` is there); it has to come from the user's own IPSW and must not
be committed. With `metal=1` alone the window server keeps GL, and a process that runs
`metal_props on` can use Metal for its own work.

Status: `libOSMesa.8.dylib` 11.9 MB with the `rwa_*` calls, `air_run` 8.1 MB, the Metal bundle
and dylib build, and the system/root images contain all of it. Hardware verification is
pending (no phone connected). The A32's test60 validated the same public driver on the same
Mali-G52 family; the A22's panel/GPU run is the next step.
