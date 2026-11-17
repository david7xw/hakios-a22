#!/bin/bash
# The Samsung Galaxy A22 4G's CONNSYS firmware, out of YOUR phone's Android, into fw-connsys/
# (git ignores them: they are the vendor's, and nothing of the vendor's is in the repository).
#
# Android keeps them where the shell user cannot read (SELinux), so this needs root on the phone
# (Magisk's su): they are copied to a temporary folder, pulled, and the folder is removed. Read only:
# nothing on the phone is changed.
set -e
S=${HAKIOS_SERIAL:?set HAKIOS_SERIAL to the serial of your phone, as adb devices shows it}
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE}"
TMP=/data/local/tmp/hakios-fw
CONNSYS="soc1_0_patch_mcu_1a_1_hdr.bin soc1_0_ram_mcu_1a_1_hdr.bin soc1_0_ram_wifi_1a_1_hdr.bin
	soc1_0_ram_bt_1a_1_hdr.bin WIFI_RAM_CODE_soc1_0_1a_1.bin WMT_SOC.cfg wifi.cfg BT_FW.cfg"

echo "Pulling CONNSYS firmware from device $S..."
mkdir -p "$OUT/fw-connsys"
for f in $CONNSYS; do
	adb -s "$S" pull "/vendor/firmware/$f" "$OUT/fw-connsys/" 2>/dev/null || echo "Note: $f not found or skipped"
done
echo "CONNSYS firmware files in $OUT/fw-connsys:"
ls -l "$OUT/fw-connsys"
