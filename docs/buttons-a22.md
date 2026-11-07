# Buttons on the A22: one in the keypad, two in the PMIC

The three buttons are not all on the same controller, and the device tree says why.

| button | where | register |
| --- | --- | --- |
| volume up | MTK keypad at `0x10010000` | `KP_MEM1` (`+0x004`) bit 1, clear while down; `kpd-hw-init-map` index 1 = `0x73` (`KEY_VOLUMEUP`) |
| volume down | MT6358 PMIC **homekey** | `TOPSTATUS` (`0x28`) bit 3, clear while down |
| power | MT6358 PMIC pwrkey | `TOPSTATUS` bit 1, clear while down |

The keypad map in the A22's device tree has only index 1 filled (`0x73`). Volume down is the
PMIC's homekey: Android's keypad driver reports the homekey interrupt as `KEY_VOLUMEDOWN`
(`kpd-sw-rstkey` `0x72` in `mediatek,kp`, see `mt6358/v1/pmic_irq.c` and
`hal_kpd.c`'s `kpd_pmic_rstkey_hal`). Power was already known from the Infinix port.

The PMIC is reached through the **pwrap** at `0x1000d000` (WACS2 command/read data/VLDCLR),
the same code the touch driver uses for VCAMA2.

## Reading it

A thread looks every 20 ms; a key has to read the same twice in a row before it counts.
The A32's pressed reads are (kept for the register layout):

```
volume up    keypad 0xfbfd 0xeff7   (MEM1 bit 1, plus matrix ghosts in MEM2)
volume down  PMIC   0x6             (TOPSTATUS was 0xe; bit 3 clears)
power        PMIC   0xc             (bit 1 clears)
```

`keylog=1` prints every change, `keyraw=1` prints all five `KP_MEM` registers and `TOPSTATUS`
whenever any of them changes.

## The A22: who enables the keypad

Android's `kpd` driver is what configures the keypad pins, writes the debounce and sets
`KP_EN` (`+0x24`) to start the scan. Booting XNU through the loader skips that driver, and the
A22's keypad block was left disabled, so `KP_MEM1` read `0xffff` and volume up never appeared.
The XNU driver only reads the block.

`mtkloader` now prepares it before `run_xnu()`: GPIO91/92 (`KPROW1`/`KPROW0`) and GPIO93/94
(`KPCOL0`/`KPCOL1`) are selected as function 1, `KP_DEBOUNCE` is set to the device tree's 1024,
the double-key bit is cleared and `KP_EN` is set to 1. It leaves pins 89/90/95 alone, which
the touch driver owns. The loader prints the mode and the first `KP_MEM1`/`KP_MEM2` values.

The PMIC homekey is still read from `TOPSTATUS` bit 3; if the A22 wires volume down to the
keypad instead, the `keyraw=1` log will show which `KP_MEM` bit moves. Power is unchanged.

## Result

The A32's `xnu-a32-emmc-test34-keys2.img` (`buttons=2 keylog=1 keyraw=1`) had all three buttons
working. On the A22 the keypad bring-up is in the loader and is being tested with
`buttons=2 keylog=1 keyraw=1`; the PMIC homekey path is unchanged.
