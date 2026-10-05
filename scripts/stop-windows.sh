#!/usr/bin/env bash
# Stop the Windows workstation and give the GPU back to Linux.
#   scripts/stop-windows.sh            re-runs itself with sudo when needed
#   scripts/stop-windows.sh --dry-run   show the plan only
set -Eeuo pipefail
HGW_TAG=stop-windows
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

# Elevate BEFORE stopping Windows, so we never stop it and then fail on privileges.
if [ $DRY = 0 ]; then ensure_root "$@"; fi
load_config
need_docker
find_container || warn "$FIND_ERR (assuming no Windows container)"

detect_state
log "current state: $STATE"
case "$STATE" in
  LINUX) log "GPU is already owned by Linux. READY FOR LINUX"; exit 0 ;;
  INCONSISTENT) die "inconsistent state ($STATE_REASON). Refusing to act. See docs/troubleshooting.md" ;;
esac

if [ $DRY = 1 ]; then
  log "plan (nothing is changed):"
  if [ "$STATE" = WINDOWS ]; then log "  1. docker stop -t ${STOP_TIMEOUT} $WINDOWS_CONTAINER (graceful), wait for QEMU to exit"
  else log "  1. Windows is already stopped: nothing to stop"; fi
  log "  2. wait for $(vfio_node) to be released"
  log "  3. gpu-to-linux.sh (VFIO -> NVIDIA), nvidia-smi, optional CDI"
  exit 0
fi

refuse_if_mocked   # everything below modifies the system
stopped() { ! container_running && [ -z "$(qemu_pids any)" ]; }

if [ "$STATE" = WINDOWS ]; then
  log "stopping Windows gracefully (up to ${STOP_TIMEOUT}s)"
  timeout "$((STOP_TIMEOUT + 30))" docker stop -t "$STOP_TIMEOUT" "$WINDOWS_CONTAINER" >/dev/null \
    || die "docker stop failed or timed out. Windows may still be running; GPU NOT released"
  wait_until 30 stopped || die "QEMU still alive after container stop; GPU NOT released"
fi

"$DIR/gpu-to-linux.sh" || die "VFIO -> Linux failed. State left as-is for inspection (scripts/status.sh)"
log "READY FOR LINUX"
