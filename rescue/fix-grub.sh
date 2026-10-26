#!/bin/sh
PATH=/bin:/sbin
# fix-grub.sh <esp> <root> <grub.cfg>  (busybox rescue, HTTP-telemetry heavy)
B=http://192.0.2.10:8092/t
tel() { wget -q -O /dev/null "$B/$1" 2>/dev/null; }
san() { tr -c 'a-zA-Z0-9_.-' '_' | cut -c1-150; }
ESP="$1"; ROOT="$2"; G="$3"
mkdir -p /tmp 2>/dev/null
[ -n "$G" ] || { tel fgnogrbcfg; exit 1; }
tel fg-start
i=0
while [ $i -lt 5 ]; do
  [ -f "$G" ] && break
  G2=$(find /esp -name grub.cfg 2>/dev/null | head -1)
  [ -n "$G2" ] && G="$G2"
  sleep 2; i=$((i+1))
done
tel "cfg-$(echo "$G" | san)"
tel "sz-$(wc -c < "$G" 2>/dev/null)"
# exfil every linux/initrd line -> visible in server access log
awk '/linux |initrd |menuentry|submenu/{print NR": "$0}' "$G" 2>/dev/null | head -30 | while IFS= read -r ln; do
  tel "L$(echo "$ln" | san)"
  sleep 0.3
done
awk -f /fix-grub.awk "$G" > /tmp/awk.out 2>/tmp/awk.err
tel "awk-lines-$(wc -l < /tmp/awk.out)-err$(wc -c < /tmp/awk.err)"
: > /tmp/cands.txt
while read -r TAG KEY GEN KF IF_; do
  [ "$TAG" = "CAND" ] || continue
  [ -f "$ESP$KF" ] || { tel "no-k-$KEY"; continue; }
  [ -f "$ESP$IF_" ] || { tel "no-i-$KEY"; continue; }
  echo "$GEN $KEY" >> /tmp/cands.txt
done < /tmp/awk.out
tel "cands-$(wc -l < /tmp/cands.txt)"
BEST=$(sort -rn /tmp/cands.txt | head -1 | cut -d' ' -f2)
[ -n "$BEST" ] || { tel fg-nopick; exit 1; }
KEY=$(printf '%s' "$BEST" | tr -dc '0-9>')
tel "pick-$KEY"
sed -i "s|^set default=.*|set default=\"$KEY\"|" "$G"
sed -i "s|^set saved_entry=.*|set saved_entry=\"$KEY\"|" "$G"
grep -q "^set default=" "$G" || printf 'set default="%s"\n' "$KEY" >> "$G"
rm -f "$ESP"/grub/grubenv "$ESP"/boot/grub/grubenv /esp/grub/grubenv 2>/dev/null
sync
tel "done-$KEY"
grep -q "default=\"$KEY\"" "$G" && tel verified
exit 0
