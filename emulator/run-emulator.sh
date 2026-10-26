set -e
K=/nix/store/92id8yn2g9kj7bskld42p222pmk3y3ms-linux-6.18.35/bzImage
timeout 150 /tmp/qemu-link/bin/qemu-system-x86_64 \
  -enable-kvm -m 2048 -smp 2 \
  -kernel $K \
  -initrd /srv/pxe-rescue/pxe/http/rescue-initrd.cpio.zst \
  -append "init=/init console=ttyS0,115200n8 loglevel=7" \
  -drive file=/tmp/target-emulator-disk.img,if=none,id=disk0,format=raw \
  -device nvme,drive=disk0,serial=emu1234 \
  -nic user,model=e1000 \
  -display none -serial mon:stdio -no-reboot > /tmp/emu-boot.log 2>&1
echo EMU-EXIT=$?
