#!/bin/bash
#
# backup scripts for rpi, only work for image generated by `gen-arch_rpi.sh` 
# usage: chmod +x bkup_alarm.sh && sudo ./bkup_alarm.sh
# 

set -xe

die() {
	printf '\033[1;31mERROR:\033[0m %s\n' "$@" >&2  # bold red
	exit 1
}

if [ "$(id -u)" -ne 0 ]; then
	die 'This script must be run as root!'
fi

which rsync > /dev/null || die 'please install rsync first'

BUILD_DATE="$(date +%Y-%m-%d)"

: ${OUTPUT_IMG:="${BUILD_DATE}-arch-rpi-bkup.img"}

: ${SRCDIR:="/dev/mmcblk0"}

cd "$(dirname "$0")"

DEST=$(pwd)

USED_ROOT_SIZE=$(df -h | grep $(findmnt / -o source -n) | awk 'END {print $3}'| grep -Eo "[0-9]+\.[0-9]+")

IMAGE_SIZE=$(awk "BEGIN {print $USED_ROOT_SIZE+0.8; exit}")

fallocate -l ${IMAGE_SIZE}G "$OUTPUT_IMG"

sfdisk -d $SRCDIR | sfdisk --force "$OUTPUT_IMG"

do_format() {
	mkfs.vfat "$BOOT_DEV"
	mkfs.ext4 "$ROOT_DEV"
	mkdir -p mnt
	mount "$ROOT_DEV" mnt
	mkdir -p mnt/boot
	mount "$BOOT_DEV" mnt/boot
}

umounts() {
	umount mnt/boot
	umount mnt
	losetup -d "$LOOP_DEV"
}

migrate_system() {
	rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","${DEST}/${OUTPUT_IMG}","${DEST}/mnt/","/lost+found"} / ${DEST}/mnt
}

LOOP_DEV=$(losetup --partscan --show --find "${OUTPUT_IMG}")
BOOT_DEV="$LOOP_DEV"p1
ROOT_DEV="$LOOP_DEV"p2

do_format

migrate_system

# recreate triggers

chroot ${DEST}/mnt /bin/bash <<-EOF
	if ! grep -q "sleep" /etc/systemd/system/resize2fs-once.service; then
		sed -i "10i ExecStartPre=/bin/sleep 10" /etc/systemd/system/resize2fs-once.service
	fi
	#systemctl daemon-reload
	systemctl enable resize2fs-once.service
EOF

umounts

cat >&2 <<-EOF
	---
	Backup is complete
	Restore with: dd if=${OUTPUT_IMG} of=/dev/TARGET_DEV bs=4M status=progress
	
EOF
