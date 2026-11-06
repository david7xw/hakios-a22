# Touch on the A22: STM FTS5CU56A or Melfas MSS100 on I2C6

The A22 was built with two possible touch controllers, chosen by the panel revision and read
from `TSP_ICID` (GPIO28). The kernel's driver, `kernel/bsd/dev/hakios.fts.c`, probes both: STM
first at `0x49`, then Melfas at `0x48`. Everything below is behind `touchscreen=3`.

| | STM FTS5CU56A | Melfas MSS100 |
| --- | --- | --- |
| I2C address | `0x49` (write `0x92`, read `0x93`) | `0x48` (write `0x90`, read `0x91`) |
| product | `ST05120022` | `MSS100` / the A22's `mss100_a22.bin` |
| resolution | 15×33 nodes | read from `0x01/0x10` |
| event | 16 bytes, one per read of `0x60` | 16 bytes each, packet info at `0x02/0x10`, data at `0x02/0x11` |
| init | sense on (`0x50`), clear-all (`0x51`) | normal touch mode (`0x06/0x13 = 0`), trigger `INTR` (`0x06/0x11 = 1`) |

Samsung's Linux sources are `drivers/input/sec_input/stm/` and
`drivers/input/sec_input/melfas/` in the A22 kernel tree; the register addresses and the event
layout below are theirs. No code is copied from them.

## The bus, by hand

There is no I2C framework in XNU, so the two pins are driven directly:

| | |
| --- | --- |
| SCL | GPIO89, function 0 (`GPIO_MODE11` at `0x10005000 + 0x3b0`, bits 7:4) |
| SDA | GPIO90, same register, bits 11:8 |
| pull-ups | `iocfg_0` at `0x10002000`: PU `+0x60` bits 23 and 25, PD `+0x50` the same bits |
| speed | about 100 kHz (4 µs per half period) |

Open drain by direction: a pin is pulled low by making it an output at 0 and let go by making
it an input again; the pull-up brings it back. Reads are one write of the command byte, a
repeated start, then the data.

## Power: two rails, and a power cycle is the only reset

| rail | what | how it is switched on |
| --- | --- | --- |
| GPIO4 | 1.8 V I/O (`tsp_en_1p8_ldo`) | output high |
| PMIC VCAMA2 | 3.0 V analog (`tsp_avdd_ldo`) | MT6358 `VCAMA2_CON0` bit 0, `OP_EN` bit 0, `ANA_CON0` VOSEL 3.0 V |

Both are needed: with only GPIO4 on, the controller answers on I2C but never reports a finger.
The device tree gives neither controller a reset GPIO, so the rails are also the reset. Android
leaves the chip powered and, when its screen is off, in low-power/AOT mode. A warm boot into
XNU does not power-cycle it. The driver therefore switches VCAMA2 off, waits 4 ms, drives GPIO4
low, waits 20 ms, then brings GPIO4 high first, waits 1 ms, and enables VCAMA2, followed by
100 ms for the controller's own power-on. That is Samsung's `sec_input_power()` order, and it
is what makes the chip return to its power-on state before the first I2C read.

## STM: the one that was already documented

The STM keeps its firmware in its own flash; Linux reads the version and only updates it when
the file is newer, so by the time XNU runs the chip is up and answering. Events are 16 bytes:

```
byte 0   bits 1:0 event id, bits 5:2 finger (0..9), bits 7:6 action (1 press, 2 move, 3 release)
byte 1   x >> 4
byte 2   y >> 4
byte 3   bits 7:4 x & 0xf, bits 3:0 y & 0xf
```

The driver sends sense on, waits, clears all events, then polls one event at a time.

## Melfas: packet info then 16-byte events

The Melfas exposes a packet-info byte at `0x02/0x10`:

```
bit 7     0: a coordinate packet, 1: an alert packet
bits 6:0  number of items
```

For a coordinate packet the driver reads `number * 16` bytes from `0x02/0x11`; each event has
the same first four bytes as the STM but the finger id is **1-based** (Linux's
`melfas_ts_coordinate_event()` does `t_id = tid - 1`):

```
byte 0   bits 1:0 event id, bits 5:2 tid (1..10), bits 7:6 action (1 press, 2 move, 3 release)
byte 1   x >> 4
byte 2   y >> 4
byte 3   bits 7:4 x & 0xf, bits 3:0 y & 0xf
```

For an alert packet the count is a number of **bytes**, not events; those bytes are read and
drained, not decoded as touches. The driver logs the first alert bytes and does not treat them
as fingers.

The controller's own state is two control registers:

| register | value | meaning |
| --- | --- | --- |
| `0x06/0x13` | 0 | normal touch (1 is low-power/AOT) |
| `0x06/0x11` | 1 | report events on the interrupt/event engine (`INTR`; 0 is `NONE`, 2 is `REG`) |
| `0x06/0x00` | read | ready status: `0xA0` none, `0xA1` log, `0xAD` ready |

On init the driver reads the product name, resolution, firmware version, node counts and ready
status, asks for normal touch and reads the mode back until it matches, then sets the trigger
to `INTR`. If no finger arrives it repeats the mode/trigger request once a minute.

## What went wrong before

The first Melfas support enabled the rails but did not cycle them, and it wrote the control
registers on a chip that might still be in Android's AOT state. The later commit removed the
control writes entirely, which left the chip asleep after a warm boot and left the event
decoder treating a move as a press. The fix in this tree does all of it: power-cycle, verify
the mode, set the trigger, decode 1-based ids, and post `MOVE` for a move.

## Reading a run

`touchscreen=3` prints, once a minute:

```
fts: so far N events, M finger positions, K status events in R reads (E failed); ...
melfas: power state before xx (want 00)
melfas: 'MSS100...' at 0x48
melfas: detected Melfas MSS100 at 0x48 (resolution 4096x4096)
```

The first twelve coordinate events are printed raw (`melfas: event ... id ... action ...`), so
a log tells whether the chip is answering, whether the ids are 1-based, and whether the action
values match. `touch_lat=1` adds a timestamped line per event; `touch_poll_us=N` changes the
polling interval (default 8000 µs).
