#!/usr/bin/env bash
# Stop the Windows workstation and give the GPU back to Linux.
#   sudo scripts/stop-windows.sh
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

load_config
need_docker
[ $DRY = 1 ] || require_root   # check BEFORE stopping Windows, so we never stop it and then fail on privileges

detect_state
log "current state: $STATE"
case "$STATE" in
  LINUX) log "GPU is already owned by Linux. READY FOR LINUX"; exit 0 ;;
  INCONSISTENT) die "inconsistent state ($STATE_REASON). Refusing to act. See docs/troubleshooting.md" ;;
esac

if [ $DRY = 1 ]; then
  log "plan:"
  [ "$STATE" = WINDOWS ] && log "  1. docker compose stop $WINDOWS_SERVICE (graceful, timeout ${STOP_TIMEOUT}s)"
  log "  2. wait for QEMU to exit and $(vfio_node) to be released"
  log "  3. gpu-to-linux.sh (VFIO -> NVIDIA), nvidia-smi, optional CDI"
  exit 0
fi

stopped() { ! container_running && [ -z "$(qemu_pids any)" ]; }

if [ "$STATE" = WINDOWS ]; then
  log "stopping Windows gracefully (up to ${STOP_TIMEOUT}s)"
  timeout "$((STOP_TIMEOUT + 30))" docker stop -t "$STOP_TIMEOUT" "$WINDOWS_CONTAINER" >/dev/null \
    || die "docker stop failed or timed out. Windows may still be running; GPU NOT released"
  wait_until 30 stopped || die "QEMU still alive after container stop; GPU NOT released"
fi

"$DIR/gpu-to-linux.sh" || die "VFIO -> Linux failed. State left as-is for inspection (scripts/status.sh)"
log "READY FOR LINUX"
