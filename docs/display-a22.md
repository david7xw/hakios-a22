# Display on the A22: command-mode DSI, the watcher and the busy check

The panel is Samsung's `s6e3fc3_a22` (rev 2), 720×1600, in **command mode**: nothing is scanned out
until the host writes a frame and kicks the DSI (`mtk_dsi_kick`).

LK leaves the display with OVL0 layer 0 pointing at its own framebuffer:
`0x79c50000`, pitch `0x0b80` = 2944 bytes (736 pixels) and the panel already initialised. XNU's console
writes `0x00rrggbb` and LK had per-pixel alpha on, which made those pixels transparent; the
loader turns alpha off and gives XNU's colour table `0xff` alpha besides.

## What was missing

Sending the frame once is not enough. The first kick showed the Apple logo and then froze:
the panel needs a new kick for every frame, and it must not be kicked while the previous
frame is still going out. The working arrangement:

- a **watcher thread on core 2** (four cores in total) writes, every 16 ms, but only if
  `0x1401400c` bit 31 (DSI busy) is clear:

  ```
  0x14001030 = 0x90380      MUTEX_MOD0
  0x14001020 = 1            MUTEX_EN
  0x1400102c = 0            MUTEX_SOF
  0x14014060 = 1            DSI_CMDQ_SIZE
  0x14014000 = 1            DSI_START
  ```

  with the command already in `0x14014000 + 0x...`'s queue (`DSI_CMDQ0 = 0x002c3909`,
  the `0x2C` "write memory start" short packet).
- the kernel's own per-frame kick is disabled: `mtk_kick=0` in
  `iokit/Kernel/MiniIOMobileFramebuffer.cpp`.

The DSI busy check was the piece that made the whole home screen appear; without it the
second frame was written over the first one's transfer and the panel stayed on the logo.

## The kernel-side kick (`mtk_kick=1`, `te_sync=1`)

The A22 still uses the loader's watcher (`mtk_kick=0`). The presenter also has the A32's
kernel-side path now, for when the watcher is turned off:

- `mtk_panel_idle(50)` waits for `0x1401400c` bit 31 to clear before composition and again in
  `mtk_panel_kick()`, so the previous frame is out of the DSI before the framebuffer is drawn
  over.
- `te_sync=1` polls the panel's TE signal on GPIO44 and starts the transfer on an edge, with a
  one-time fallback if no edge is seen. It is off by default: the A32 measured two edges per
  frame and a timeout that cost frames, so it is opt-in.
- each queued swap remembers the GPU job its surfaces stood for, and `show()` waits for that
  job, not for the surface's live sequence. A later read-only job on the same surface (a blur
  behind a sheet) no longer makes the frame wait.

None of these have been measured on the A22 yet; with `mtk_kick=0` they do nothing.

## Result

`a22diag` proved the display pipeline: color bars and countdown showed crisply at 720×1600.
`fbscale=2` gives native 360×800 logical points.
## Cores

Six cores were tried and the phone ended in fastboot; eight leave no core for the watcher.
Four is the stable choice, and the watcher needs one of them.
