#!/bin/bash
# Build a fake TARGET NVMe image: GPT p1=vfat ESP (with fake generations), p2=btrfs with REAL fsid at 65568
set -e
IMG=/tmp/target-emulator-disk.img
rm -f $IMG /tmp/zesp.img /tmp/zroot.img
truncate -s 256M $IMG
truncate -s 50M /tmp/zesp.img
truncate -s 150M /tmp/zroot.img
mkfs.vfat -F 32 /tmp/zesp.img >/dev/null
mkfs.btrfs -f -q -U REPLACE-BTRFS-FSID /tmp/zroot.img >/dev/null

# stage grub.cfg + kernels on ESP (mtools since loop mount needs root caps we may not have)
mmd -i /tmp/zesp.img ::/grub
# gen6: crash-module gen (should be SKIPPED by fixer)
cp /tmp/grub.cfg.emu /tmp/grub.cfg
mcopy -i /tmp/zesp.img /tmp/grub.cfg ::/grub/grub.cfg
mmd -i /tmp/zesp.img ::/kernels
for g in 6 5 4 3; do
  head -c 200000 /dev/zero > /tmp/k
  mcopy -i /tmp/zesp.img /tmp/k ::/kernels/g${g}bz
  mcopy -i /tmp/zesp.img /tmp/k ::/kernels/g${g}ir
done
rm -f /tmp/k

# GPT on the big image: p1 50M vfat, p2 rest btrfs
sfdisk -q $IMG <<EOF
label: gpt
start=2048, size=102400, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
start=104448, size=307200, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
# splice images into partitions via kpartx-free offset math: p1 at 2048*512, p2 at 104448*512
dd if=/tmp/zesp.img of=$IMG bs=1M skip=0 seek=1 count=50 conv=notrunc status=none
dd if=/tmp/zroot.img of=$IMG bs=1M seek=51 count=150 conv=notrunc status=none
# verify fsid lands at 65568 inside p2 => abs offset 104448*512 + 65568
ABS=$((104448*512 + 65568))
dd if=$IMG bs=1 skip=$ABS count=16 2>/dev/null | od -An -tx1 | tr -d ' \n'; echo
echo FAKE-NVME-READY