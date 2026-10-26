# NixOS blind boot-loop recovery over PXE (AMT-armed, no keyboard, no monitor)

A proven recipe for unbricking a **remote** NixOS box that boot-loops after a bad
`nixos-rebuild switch` — when you are not physically near it, there is no monitor,
no keyboard, no IPMI/KVM (Intel AMT 9.x on this box gives power control + one-time
PXE boot, nothing visual).

The real-world incident: a hand-rolled kexec crash-capture module shipped an
initrd unit with no `ConditionKernelCommandLine=` guard and `reboot-force` on
failure. Every boot = reboot. GRUB timeout = 5 s, so even a keyboard couldn't
catch the menu. The box was repaired fully remotely and came back on generation
11 with zero data loss.

## How it works (top level)

```
[you] --AMT WS-Man--> arm one-time PXE + hard reset
                         |
   box PXE-boots --------+--> dnsmasq proxyDHCP -> undionly.kpxe (embedded iPXE)
                         |                              | chain
                         |                     HTTP boot.ipxe -> rescue bzImage
                         |                                  + busybox rescue initrd
                         v
   rescue init:  probe NVMe -> mount ESP -> find BTRFS root by FSID
                -> rewrite GRUB `default=` to newest SAFE generation
                -> write /esp/rescue.done marker -> reboot to disk
   next PXE boot sees marker, boots disk immediately (idempotent loop-breaker)
```

Since there is **no console visibility at all**, the rescue initrd phones home
with `wget` to the PXE server, one distinct URL path per step; the darkhttpd
access log becomes your serial console.

## Contents

| Path | What |
|---|---|
| `amt/pxe_boot.py` | Arm one-time PXE + hard reset over AMT WS-Man (needs [james_crowley.intel_amt](https://github.com/james-crowley/ansible_intel_amt) lib, `AMT_PASSWORD` env var) |
| `amt/power_state.py` | Read AMT power state |
| `pxe/dnsmasq-proxydhcp.conf` | proxyDHCP-only config (router keeps leasing; we only steer boot files) |
| `pxe/embed.ipxe` | Script embedded into `undionly.kpxe` (kills all stage-2 DHCP fragility) |
| `pxe/boot.ipxe` | Served over HTTP; fetches rescue kernel + initrd |
| `rescue/build-rescue.sh` | Builds the busybox rescue initrd from Nix store modules (`zstd -19` cpio) |
| `rescue/initrd/init` | The rescue logic: mount ESP, BTRFS probe, GRUB fix, telemetry, reboot |
| `rescue/fix-grub.sh` + `rescue/fix-grub.awk` | Busybox-awk GRUB stage-1 parser: picks newest generation whose kernel lacks `crashkernel=`, handles submenus |
| `emulator/` | QEMU fake-NVMe harness: run the whole rescue against a fake ESP+BTRFS disk **before** touching the target |

## Setup on the PXE server (this run: NixOS, any Linux works)

```sh
# 1. dirs
mkdir -p /srv/pxe-rescue/{tftp,http/t}

# 2. iPXE binaries (nix: `nix-build -A ipxe`; copy undionly.kpxe + ipxe.efi to tftp/)
#    then embed the chain script so stage-2 needs no special DHCP answers:
#    (see pxe/embed.ipxe; build with ipxe.override { embedScript = ...; })

# 3. rescue initrd
./rescue/build-rescue.sh
cp /srv/pxe-rescue/http/rescue-* /srv/pxe-rescue/tftp/

# 4. services
dnsmasq --no-daemon -C pxe/dnsmasq-proxydhcp.conf
darkhttpd /srv/pxe-rescue/http --addr 0.0.0.0 --port 8092 --log /tmp/http-access.log
```

Edit these site values first (grep for `192.0.2.`, `REPLACE-`):
PXE-server/box IPs, server MAC (static ARP — the rescue init has no full DHCP),
and your BTRFS root FSID (get it once from a healthy boot: `blkid -s UUID` of the
root, dashes stripped, lowercase, it's the same 16 bytes at offset 65568).

## Fire

```sh
export AMT_PASSWORD=***          # never in the repo
python3 amt/pxe_boot.py          # -> "one-time PXE boot ARMED" + "HARD-RESET-SENT"
tail -f /tmp/http-access.log     # your console; expect /t/01start, /t/esp-...,
                                 # /t/pick-1>N, /t/done-1>N, /t/verified, /t/13result-ok
```

When you see `/t/13result-ok` the GRUB default is rewritten; the box reboots into
the chosen generation. `SSH-OPEN` a couple of minutes later = recovered.

## The pitfalls that cost hours (read before writing your own)

1. **netconsole never worked on the real box** despite correct syntax; HTTP
   `wget` telemetry through the PXE server's access log worked first try.
   Use HTTP, keep netconsole as decoration.
2. **darkhttpd logs strip query strings.** One distinct *path* per step
   (`/t/07net-eno1`), not `?step=7net`.
3. **dnsmasq proxyDHCP + iPXE stage 2 is a minefield.** The robust fix: embed
   the chain script inside `undionly.kpxe` so iPXE never asks DHCP again —
   plus tag `dhcp-boot` on `dhcp-userclass=set:ipxe,iPXE`. A `pxe-service`
   line for iPXE clients pushes it back into PXE-discovery loops; don't.
4. **Busybox interpreter trap**: the initrd must contain glibc at the exact
   `/nix/store/<hash>-glibc-*/` path baked into busybox's `PT_INTERP`, or init
   dies instantly and silently. Mirror the store paths.
5. **Module load order**: use `modules.order`/DFS post-order (`insmod` fails
   silently otherwise, then NVMe never appears). `nvme-core` before `nvme`,
   plus `crc32c-crypto`, `crc-itu-t`, `raid6-recov`, `xor`, `poly1305`,
   `nls_ascii`, `nls_cp437`, `fat`, `vfat` before `btrfs`.
6. **NVMe enumeration is slow after a hard reset** — poll for
   `/sys/class/block/nvme*n1p1` up to 30 s before giving up on disks.
7. **Real NixOS stage-1 `grub.cfg`** differs from toy fixtures:
   - titles are `Configuration 13` (not "Generation") in recent stage-1,
   - entries are indented with **tabs**, titles in **single quotes**,
   - `linux (drive1)/kernels/...` paths carry a **GRUB device prefix** — strip
     `(...)` before checking the file on the mounted ESP,
   - older generations live inside `submenu 'NixOS - All configurations'` —
     GRUB `default=` for them is `T>C` (0-based submenu index > 0-based entry
     index), not a bare number.
   Validate your fixer against a **realistic fixture** in QEMU; a naive fixture
   "passes" while the fixer finds zero candidates on real hardware.
8. **Exfil the config** — the init uploads sanitized `grub.cfg` lines via the
   telemetry URL. That's how the `(drive1)/` prefix bug was found remotely.
9. **Idempotency**: `/esp/rescue.done` marker checked at boot makes repeated
   PXE fires harmless once the fix landed.
10. Keep a `grub.cfg.rescuebak` copy before rewriting. Done.

## Emulator first, always

```sh
./emulator/build-emulator-disk.sh   # fake GPT+ESP+FAT grub.cfg+BTRFS @ root via loop
./emulator/run-emulator.sh          # QEMU boots the rescue against it; expect V8-RESULT=OK
```

Only fire at real hardware after the emulator prints
`CAND 1>N <gen> ...` -> `V8-RESULT=OK` against the **realistic** fixture
(`emulator/grub.cfg.fixture`: tabs, single quotes, submenu, `(drive1)/` prefix).

## Security notes

- AMT 9.x is EOL and pre-auth vulnerable (CVE-2017-5689 class) — LAN-only,
  never exposed, ideally firewalled to the PXE server.
- No credentials in this repo: AMT password via env var, rescue init carries
  no SSH keys, target access after recovery is your normal root auth.
- The rescue initrd mounts the root read-write to fix GRUB config files only
  (plus optional module disable); keep it surgical.
