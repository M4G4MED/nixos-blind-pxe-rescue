# TARGET rescue GRUB candidate extractor v5 (busybox awk)
# Real NixOS grub.cfg: single-quoted titles, TAB-indented entries, older gens in submenu.
# Output: CAND <grub-addr> <gen> <kernel> <initrd>   (addr "N" top-level, "T>C" submenu)
# DBG lines carry sanitized titles for HTTP exfil.
BEGIN { topidx = 0; subidx = 0; insub = 0; capture = 0; subtop = 0 }
{
  line = $0
  sub(/\r$/, "", line)
  sub(/^[ \t]+/, "", line)
}
line ~ /^(#[^ ]|[$}])/ { next }
line ~ /^submenu[ \t]/ {
  if (capture) {
    if (!hascrash && curkrn != "" && curini != "") emit()
    capture = 0
  }
  subtop = topidx      # submenu's own 0-based top-level index
  topidx++
  insub = 1; subidx = 0; next
}
line ~ /^menuentry[ \t]/ {
  if (capture) {
    if (!hascrash && curkrn != "" && curini != "") emit()
  }
  p = index(line, "'")
  q = 0
  if (p > 0) {
    rest = substr(line, p + 1)
    q = index(rest, "'")
  }
  if (q > 0) title = substr(rest, 1, q - 1)
  else {
    p = index(line, "\"")
    rest = substr(line, p + 1)
    q = index(rest, "\"")
    title = (q > 0) ? substr(rest, 1, q - 1) : line
  }
  gsub(/[^a-zA-Z0-9 ]/, "", title)
  curkey = (insub) ? (subtop ">" subidx++) : ("" topidx++)
  curkrn = ""; curini = ""; hascrash = 0
  gpos = match(title, /Generation [0-9]+/)
  if (gpos) curgen = substr(title, gpos + 11, RLENGTH - 11) + 0
  else {
    gpos = match(title, /[0-9]+/)
    curgen = gpos ? substr(title, gpos, RLENGTH) + 0 : -1
  }
  capture = 1
  next
}
line ~ /^}[ \t]*$/ {
  if (capture) {
    if (!hascrash && curkrn != "" && curini != "") emit()
    capture = 0
  }
  next
}
capture && line ~ /^linux[ \t]/ {
  if (line ~ /crashkernel/) hascrash = 1
  n = split(line, w, /[ \t]+/)
  sub(/^\([^)]*\)/, "", w[2])   # strip GRUB device prefix like (drive1)
  curkrn = w[2]
  next
}
capture && line ~ /^initrd[ \t]/ {
  n = split(line, w, /[ \t]+/)
  sub(/^\([^)]*\)/, "", w[2])
  curini = w[2]
  next
}
function emit() {
  print "CAND", curkey, curgen, curkrn, curini
}
END {
  if (capture && !hascrash && curkrn != "" && curini != "") emit()
}
