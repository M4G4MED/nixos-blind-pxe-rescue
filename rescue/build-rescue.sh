#!/bin/bash
# Rescue initrd v5 for TARGET boot-loop recovery.
# - busybox + glibc mirrored at REAL nix-store paths (PT_INTERP satisfies)
# - this server's 6.18.35 modules (btrfs/nvme/vfat/e1000e/netconsole)
# - init = /srv/pxe-rescue/rescue/init-v5 (verbose, ESP-logged, netconsole)
# - fix-grub.sh picks latest gen WITHOUT crashkernel=, validated kernel files
set -e
SRC=/run/current-system
MODSRC=$SRC/kernel-modules/lib/modules
KVER=$(basename $MODSRC/*)
WORK=/srv/pxe-rescue/rescue/stage
BB=/nix/store/5dbs0ch0ykqha1pxjhpy16gjcdy6vjs0-busybox-1.37.0/bin/busybox
GL=/nix/store/fsd4vbp9zjd9iaicq2fb9lpc1h5j973y-glibc-2.42-100
rm -rf $WORK && mkdir -p $WORK/dev $WORK/proc $WORK/sys $WORK/run $WORK/bin $WORK/modules $WORK/esp $WORK/root $WORK/tmp
cd $WORK

mkdir -p $WORK$(dirname $BB) $WORK$GL/lib
cp $BB $WORK$BB
cp $GL/lib/ld-linux-x86-64.so.2 $GL/lib/libc.so.6 $GL/lib/libm.so.6 $GL/lib/libresolv.so.2 $WORK$GL/lib/
for a in sh mount umount insmod sed grep cat mkdir sync sleep echo mknod ls dd od \
         lsmod dmesg reboot tr cut wc find head stat printf cp rm date awk \
         rmmod blkid tail xargs ip ifconfig udhcpc touch test sort wget arp ping timeout; do
  ln -sf $BB bin/$a
done

python3 - "$MODSRC/$KVER" modules <<'PY'
import sys, os, lzma, shutil
mods, dest = sys.argv[1], sys.argv[2]
graph = {}
for line in open(os.path.join(mods, 'modules.dep')):
    k, _, vs = line.partition(':')
    graph[k] = vs.split()
def base(n):
    b = os.path.basename(n)
    for s in ('.xz', '.zst', '.gz'):
        if b.endswith(s):
            return b[:-len(s)]
    return b
def find_nodes(*names):
    return [n for n in graph if base(n) in names]
seen = set()
order = []
def visit(n):
    if n in seen or n not in graph:
        return
    seen.add(n)
    for d in graph[n]:
        visit(d)
    order.append(n)   # post-order: deps land before dependents

for node in find_nodes('btrfs.ko', 'nvme.ko', 'nvme-core.ko', 'vfat.ko', 'fat.ko',
                       'e1000e.ko', 'netconsole.ko', 'crc32c-cryptoapi.ko', 'nls_cp437.ko',
                       'nls_ascii.ko', 'nls_iso8859-1.ko'):
    visit(node)
os.makedirs(os.path.join(dest, '.order'), exist_ok=True)
missing = []
with open(os.path.join(dest, '.order', 'LOAD'), 'w') as lf:
    for n in order:
        b = base(n)
        p = os.path.join(mods, n)
        if not os.path.exists(p):
            p2 = p + '.xz'
            p = p2 if os.path.exists(p2) else None
        if p is None:
            missing.append(n); continue
        out = os.path.join(dest, b)
        if p.endswith('.xz'):
            with lzma.open(p) as fi, open(out, 'wb') as fo:
                shutil.copyfileobj(fi, fo)
        else:
            shutil.copy(p, out)
        lf.write(b + '\n')
print('modules:', len(order), 'missing:', missing)
PY

cp /srv/pxe-rescue/rescue/fix-grub.sh $WORK/fix-grub.sh
cp /srv/pxe-rescue/rescue/fix-grub.awk $WORK/fix-grub.awk
cp /srv/pxe-rescue/rescue/init-v5 $WORK/init
chmod +x $WORK/init
cp /srv/pxe-rescue/rescue/crash-ssd.fixed.nix $WORK/crash-module.nix

mknod dev/console c 5 1 2>/dev/null || true
mknod dev/null c 1 3 2>/dev/null || true

find . | cpio --quiet -o -H newc 2>/dev/null | zstd -q -T0 --stdout > /srv/pxe-rescue/pxe/http/rescue-initrd.cpio.zst
cp $SRC/kernel /srv/pxe-rescue/pxe/http/rescue-bzImage
ls -la /srv/pxe-rescue/pxe/http/rescue-initrd.cpio.zst
echo RESCUE-V5-BUILT
