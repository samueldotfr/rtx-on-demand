#!/usr/bin/env bash
# Start the Windows workstation: Linux -> VFIO (if needed) -> start container -> verify passthrough.
#   sudo scripts/start-windows.sh
#   scripts/start-windows.sh --dry-run   show the plan and run read-only guards
set -Eeuo pipefail
HGW_TAG=start-windows
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
[ $DRY = 1 ] || require_root

detect_state
log "current state: $STATE"
case "$STATE" in
  WINDOWS) log "Windows is already running with the GPU. READY"; exit 0 ;;
  INCONSISTENT) die "inconsistent state ($STATE_REASON). Refusing to act. Run scripts/status.sh and see docs/troubleshooting.md" ;;
esac

if [ $DRY = 1 ]; then
  log "plan:"
  [ "$STATE" = LINUX ] && log "  1. gpu-to-vfio.sh (Linux -> VFIO)"
  log "  2. verify both functions on vfio-pci and $(vfio_node) present"
  log "  3. docker compose up -d $WINDOWS_SERVICE in ${WINDOWS_COMPOSE_DIR:-<unset>}"
  log "  4. verify container + QEMU passthrough"
  [ "$STATE" = LINUX ] && "$DIR/gpu-to-vfio.sh" --check
  exit 0
fi

if [ "$STATE" = LINUX ]; then
  "$DIR/gpu-to-vfio.sh" || die "Linux -> VFIO failed; Windows not started"
  detect_state
fi
[ "$STATE" = VFIO_PARKED ] || die "expected VFIO_PARKED before starting Windows, got $STATE ($STATE_REASON)"
[ "$(pci_driver "$GPU_PCI")" = vfio-pci ] && [ "$(pci_driver "$GPU_AUDIO_PCI")" = vfio-pci ] || die "GPU functions are not both on vfio-pci"
[ -e "$(vfio_node)" ] || die "$(vfio_node) is missing"

log "starting Windows container '$WINDOWS_CONTAINER'"
compose up -d "$WINDOWS_SERVICE" || die "docker compose up failed. GPU remains parked on VFIO (no rollback). Fix, retry, or run scripts/stop-windows.sh"

up() { container_running && [ -n "$(qemu_pids gpu)" ]; }
wait_until 60 up || die "container or QEMU passthrough not confirmed after 60s (check: docker logs $WINDOWS_CONTAINER)"
log "READY: Windows is running with the GPU (QEMU owns IOMMU group $VFIO_GROUP). Connect with Moonlight."
