#!/usr/bin/env bash
# Tests install/install-user-commands.sh in a temporary HOME and a temporary fake clone.
# Never touches the real home directory.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check(){ local d=$1; shift; if "$@"; then PASS=$((PASS+1)); echo "  PASS  $d"; else FAIL=$((FAIL+1)); echo "  FAIL  $d"; fi; }

# fake clone (path with a space on purpose) whose scripts echo their argv and exit with $FAKE_RC
CL="$T/my clone"; mkdir -p "$CL/install" "$CL/scripts"
cp "$ROOT/install/install-user-commands.sh" "$CL/install/"
for s in start-windows stop-windows status; do
  printf '#!/usr/bin/env bash\necho "%s argv:[$*] rc:${FAKE_RC:-0}"\nexit "${FAKE_RC:-0}"\n' "$s" > "$CL/scripts/$s.sh"; chmod +x "$CL/scripts/$s.sh"
done
H="$T/home"; mkdir -p "$H"; INST="$CL/install/install-user-commands.sh"

echo "== first install =="
out="$("$INST" --dest "$H" 2>&1)"; rc=$?
check "exit 0" test "$rc" = 0
check "three launchers exist and are executable" test -x "$H/start-windows.sh" -a -x "$H/stop-windows.sh" -a -x "$H/windows-status.sh"
check "launcher is 4 lines: shebang, marker, comment, exec (no logic)" test "$(wc -l < "$H/start-windows.sh")" = 4
check "exec line is the only code, and mentions no pci/vfio/docker/compose/config" bash -c "! tail -n 1 '$H/start-windows.sh' '$H/stop-windows.sh' '$H/windows-status.sh' | grep -iE 'pci|vfio|docker|compose|\.env|iommu|nvidia'"
check "start target is the clone's start-windows.sh" test "$(tail -n 1 "$H/start-windows.sh")" = "exec $(printf '%q' "$CL/scripts/start-windows.sh") \"\$@\""
check "status launcher targets scripts/status.sh" test "$(tail -n 1 "$H/windows-status.sh")" = "exec $(printf '%q' "$CL/scripts/status.sh") \"\$@\""
check "arguments propagate (including spaces)" test "$("$H/start-windows.sh" --dry-run "a b" 2>&1)" = "start-windows argv:[--dry-run a b] rc:0"
FAKE_RC=7 "$H/stop-windows.sh" >/dev/null; check "exit code propagates (7)" test "$?" = 7
FAKE_RC=0 "$H/windows-status.sh" >/dev/null; check "exit code propagates (0)" test "$?" = 0

echo "== idempotent second install =="
before="$(cat "$H"/*.sh | md5sum)"; "$INST" --dest "$H" >/dev/null 2>&1; rc=$?
check "exit 0, content identical" test "$rc" = 0 -a "$before" = "$(cat "$H"/*.sh | md5sum)"
check "no backup created for our own launchers" bash -c "! ls '$H'/*.bak-* >/dev/null 2>&1"

echo "== launcher from before the rename (legacy marker) =="
H5="$T/home5"; mkdir -p "$H5"
for n in start-windows.sh stop-windows.sh windows-status.sh; do
  printf '#!/usr/bin/env bash\n# homelab-gpu-workstation launcher\nexec /old/path/scripts/x.sh "$@"\n' > "$H5/$n"; chmod 755 "$H5/$n"
done
"$INST" --dest "$H5" >/dev/null 2>&1; rc=$?
check "replaced without --force (exit 0)" test "$rc" = 0
check "no backup created for legacy launchers" bash -c "! ls '$H5'/*.bak-* >/dev/null 2>&1"
check "new marker and new target, old path gone" bash -c "grep -qxF '# rtx-on-demand launcher' '$H5/start-windows.sh' && ! grep -q /old/path '$H5'/*.sh"

echo "== foreign file =="
H2="$T/home2"; mkdir -p "$H2"; printf '#!/bin/bash\n# precious production script\necho prod\n' > "$H2/start-windows.sh"; chmod 755 "$H2/start-windows.sh"
orig="$(md5sum < "$H2/start-windows.sh")"
"$INST" --dest "$H2" >/dev/null 2>&1; rc=$?
check "refused without --force (non-zero)" test "$rc" != 0
check "foreign file untouched" test "$orig" = "$(md5sum < "$H2/start-windows.sh")"
check "nothing else installed on refusal" test ! -e "$H2/stop-windows.sh" -a ! -e "$H2/windows-status.sh"
"$INST" --dest "$H2" --dry-run >/dev/null 2>&1; check "--dry-run with a foreign file changes nothing" test "$orig" = "$(md5sum < "$H2/start-windows.sh")"

echo "== --force: backup first =="
out="$("$INST" --dest "$H2" --force 2>&1)"; rc=$?
bak="$(ls "$H2"/start-windows.sh.bak-* 2>/dev/null | head -1)"
check "exit 0" test "$rc" = 0
check "timestamped backup exists and is non-empty" test -n "$bak" -a -s "$bak"
check "backup is byte-identical to the original" test "$orig" = "$(md5sum < "$bak")"
check "backup keeps the executable bit" test -x "$bak"
check "new launcher installed afterwards" grep -qxF "# rtx-on-demand launcher" "$H2/start-windows.sh"
check "output says the backup was verified" bash -c "printf '%s' '$out' | grep -q 'verified'"

echo "== --force with a foreign symlink =="
H3="$T/home3"; mkdir -p "$H3"; ln -s /bin/true "$H3/start-windows.sh"
"$INST" --dest "$H3" --force >/dev/null 2>&1
check "symlink backed up as a symlink, target intact" test -L "$H3"/start-windows.sh.bak-* -a -x /bin/true

echo "== installs from the REAL clone into a temp home (dry-run) =="
H4="$T/home4"; mkdir -p "$H4"
check "real installer dry-run works" "$ROOT/install/install-user-commands.sh" --dest "$H4" --dry-run
check "dry-run wrote nothing" test -z "$(ls -A "$H4")"
echo; echo "passed=$PASS failed=$FAIL"; [ "$FAIL" = 0 ]
