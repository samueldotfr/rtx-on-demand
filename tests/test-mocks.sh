#!/usr/bin/env bash
# Hardware-free tests: fake sysfs, fake /proc, fake docker/id in a temp dir.
# Never touches the real GPU, Docker or /sys: every mutating code path is refused in test mode
# (HGW_FAKE_SYSFS / HGW_FAKE_PROC) and the fake docker only LOGS what it was asked to change.
#   tests/test-mocks.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check(){ local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'D'
#!/usr/bin/env bash
case "$1" in
  ps) [ "${2:-}" = -q ] && exit 0; for n in ${MOCK_PS_NAMES-}; do echo "$n"; done ;;
  inspect) [ "$MOCK_CSTATE" = absent ] && exit 1
           case "$3" in '{{.State.Status}}') echo "$MOCK_CSTATE" ;; *) echo "${MOCK_LABEL-}" ;; esac ;;
  *) echo "MUTATION docker $*" >> "$MOCK_LOG" ;;
esac
D
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$T/bin/id"
chmod +x "$T/bin/docker" "$T/bin/id"

mk_sys() { # <dir> <gpus> <audio funcs per gpu> <gpu driver> <audio driver>
  local d=$1 i f dev slot
  mkdir -p "$d/bus/pci/devices" "$d/kernel/iommu_groups" "$d/drivers/$4" "$d/drivers/$5"
  for i in $(seq 1 "$2"); do
    slot="0000:0$i:00"; dev="$d/bus/pci/devices/$slot.0"; mkdir -p "$dev" "$d/kernel/iommu_groups/99$i/devices"
    echo 0x10de > "$dev/vendor"; echo 0x030000 > "$dev/class"; echo "(null)" > "$dev/driver_override"
    ln -s "$d/kernel/iommu_groups/99$i" "$dev/iommu_group"; ln -s "$d/drivers/$4" "$dev/driver"
    ln -s "$dev" "$d/kernel/iommu_groups/99$i/devices/$slot.0"
    for f in $(seq 1 "$3"); do
      dev="$d/bus/pci/devices/$slot.$f"; mkdir -p "$dev"
      echo 0x10de > "$dev/vendor"; echo 0x040300 > "$dev/class"; echo "(null)" > "$dev/driver_override"
      ln -s "$d/kernel/iommu_groups/99$i" "$dev/iommu_group"; ln -s "$d/drivers/$5" "$dev/driver"
      ln -s "$dev" "$d/kernel/iommu_groups/99$i/devices/$slot.$f"
    done
  done
}
mk_proc() { mkdir -p "$1/$2"; printf '%s\0' "${@:3}" > "$1/$2/cmdline"; }

# run <env assignments...> -- cmd... ; sets OUT, RC
run() {
  local envs=() ; while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  OUT="$(env PATH="$T/bin:$PATH" MOCK_LOG="$T/log" "${envs[@]}" "$@" 2>&1)"; RC=$?
}
: > "$T/log"
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
rc_has() { [ "$RC" = "$1" ] && has "$2"; }      # exit code AND message
no_mutation() { [ ! -s "$T/log" ]; }

echo "== /proc scanning (fake /proc) =="
SYS="$T/sys1"; mk_sys "$SYS" 1 1 vfio-pci vfio-pci
P="$T/proc1"; mkdir -p "$P"
mk_proc "$P" 100 qemu-system-x86_64 -device vfio-pci,host=0000:01:00.0,multifunction=on -device vfio-pci,host=0000:01:00.1
mk_proc "$P" 101 qemu-system-x86_64 -device vfio-pci,host=0000:01:00.0,multifunction=on
mk_proc "$P" 102 bash -c "echo host=0000:01:00.0 qemu-system"
mk_proc "$P" 103 qemu-system-x86_64 -m 1G
mkdir -p "$P/104"                       # pid dir without cmdline (exited): ignored
ln -s "$T/nonexistent" "$P/105-x" 2>/dev/null; rm -f "$P/105-x"
lib() { run HGW_FAKE_SYSFS="$SYS" HGW_FAKE_PROC="$P" -- bash -c ". '$ROOT/scripts/lib/common.sh'; load_config; $1"; }
lib 'qemu_pids full | tr "\n" " "';  check "full: only the process referencing both functions" test "$OUT" = "100 "
lib 'qemu_pids gpu | tr "\n" " "';   check "gpu: processes referencing either function, not non-qemu" test "$OUT" = "100 101 "
lib 'qemu_pids any | tr "\n" " "';   check "any: every qemu-system" test "$OUT" = "100 101 103 "
mkdir -p "$P/106"; ln -s "$T/nonexistent" "$P/106/cmdline"     # pid exists, cmdline unreadable (dangling)
lib 'qemu_pids any | tr "\n" " "';   check "unreadable cmdline of an existing pid is reported, not dropped" has "unreadable:106"
lib 'qemu_full_pids 2>/dev/null | tr "\n" " "';  check "unreadable marker never counts as confirmed passthrough" test "$OUT" = "100 "
rm -rf "$P/106"
if [ "$(id -u)" != 0 ]; then
  mk_proc "$P" 107 qemu-system-x86_64; chmod 000 "$P/107/cmdline"
  lib 'qemu_pids any | tr "\n" " "'; check "permission-denied cmdline is reported (fail closed)" has "unreadable:107"
  chmod 600 "$P/107/cmdline"
fi

echo "== race: processes appearing/disappearing in the REAL /proc =="
( for _ in $(seq 1 40); do for _ in $(seq 1 25); do ( : ) & done; wait; done ) &
CHURN=$!
errs=0; unread=0
for _ in $(seq 1 60); do
  out="$(env HGW_FAKE_SYSFS="$SYS" bash -c ". '$ROOT/scripts/lib/common.sh'; load_config; qemu_pids any" 2>&1)"
  case "$out" in *"No such file"*) errs=$((errs+1)) ;; esac
  case "$out" in *unreadable:*) unread=$((unread+1)) ;; esac
done
wait "$CHURN" 2>/dev/null
check "no 'No such file' noise across 60 scans under process churn" test "$errs" = 0
check "a vanished pid is never reported as unreadable" test "$unread" = 0

echo "== auto-discovery =="
S2="$T/sys2"; mk_sys "$S2" 2 1 vfio-pci vfio-pci
run HGW_FAKE_SYSFS="$S2" HGW_FAKE_PROC="$P" MOCK_CSTATE=exited MOCK_PS_NAMES=win -- "$ROOT/scripts/status.sh"
check "two NVIDIA GPUs: fail closed with a clear message" has "several NVIDIA GPUs"
S3="$T/sys3"; mk_sys "$S3" 1 2 vfio-pci vfio-pci
run HGW_FAKE_SYSFS="$S3" HGW_FAKE_PROC="$P" -- "$ROOT/scripts/status.sh"
check "two audio functions: fail closed" has "several audio functions"
S4="$T/sys4"; mk_sys "$S4" 0 0 vfio-pci vfio-pci
run HGW_FAKE_SYSFS="$S4" HGW_FAKE_PROC="$P" -- "$ROOT/scripts/status.sh"
check "no NVIDIA GPU: fail closed" has "no NVIDIA GPU"

echo "== WINDOWS -> start-windows -> WINDOWS (idempotence, fake root, no mutation) =="
PW="$T/procw"; mkdir -p "$PW"
mk_proc "$PW" 200 qemu-system-x86_64 -device vfio-pci,host=0000:01:00.0,multifunction=on -device vfio-pci,host=0000:01:00.1
run HGW_FAKE_SYSFS="$SYS" HGW_FAKE_PROC="$PW" MOCK_CSTATE=running MOCK_PS_NAMES=win -- "$ROOT/scripts/start-windows.sh"
check "exits 0 and says nothing to do" rc_has 0 "Nothing to do"
check "no docker mutation, no GPU transition attempted" no_mutation
printf '%s' "$OUT" | grep -q 'gpu-to-vfio' && bad "gpu-to-vfio was invoked" || ok "gpu-to-vfio not invoked"
PP="$T/procp"; mkdir -p "$PP"; mk_proc "$PP" 201 qemu-system-x86_64 -device vfio-pci,host=0000:01:00.0,multifunction=on
run HGW_FAKE_SYSFS="$SYS" HGW_FAKE_PROC="$PP" MOCK_CSTATE=running MOCK_PS_NAMES=win -- "$ROOT/scripts/start-windows.sh"
check "QEMU with only the GPU function (no audio): refused as inconsistent" rc_has 1 "BOTH"
check "still no mutation" no_mutation

echo "== PARKED: dry-run plans, real run is refused in test mode =="
PE="$T/proce"; mkdir -p "$PE"
run HGW_FAKE_SYSFS="$SYS" HGW_FAKE_PROC="$PE" MOCK_CSTATE=exited MOCK_PS_NAMES=win -- "$ROOT/scripts/start-windows.sh" --dry-run
check "dry-run plans 'docker start' for an existing container" rc_has 0 "docker start win"
run HGW_FAKE_SYSFS="$SYS" HGW_FAKE_PROC="$PE" MOCK_CSTATE=exited MOCK_PS_NAMES=win -- "$ROOT/scripts/start-windows.sh"
check "non-dry-run refused before any mutation in test mode" rc_has 1 "test mode"
check "fake docker received no mutation" no_mutation

echo; echo "passed=$PASS failed=$FAIL"; [ "$FAIL" = 0 ]
