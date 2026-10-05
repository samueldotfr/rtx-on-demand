#!/usr/bin/env bash
# Start the Windows workstation: Linux -> VFIO (if needed) -> start the container -> verify passthrough.
#   scripts/start-windows.sh            re-runs itself with sudo when needed
#   scripts/start-windows.sh --dry-run  show the plan and run read-only guards; changes nothing
#
# Container policy (never silently recreates the VM):
#   - container already running      -> nothing to do
#   - container exists               -> `docker start` (same devices/args/volumes as when it was created)
#   - container does not exist       -> `docker compose up -d --no-recreate` with the configured WINDOWS_COMPOSE
set -Eeuo pipefail
HGW_TAG=start-windows
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$DIR/lib/common.sh"

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

if [ $DRY = 0 ]; then ensure_root "$@"; fi
load_config
need_docker
require_container

summary() {
  echo
  echo "Windows workstation"
  echo "-------------------"
  echo "GPU driver: $(pci_driver "$GPU_PCI") / audio: $(pci_driver "$GPU_AUDIO_PCI")"
  echo "VFIO group: $VFIO_GROUP ($(vfio_node) $([ -e "$(vfio_node)" ] && echo present || echo ABSENT))"
  echo "Windows container: $WINDOWS_CONTAINER ($(container_state))"
  echo "QEMU passthrough: $([ -n "$(qemu_full_pids)" ] && echo active || echo 'NOT CONFIRMED')"
}

detect_state
CSTATE="$(container_state)"
log "state: $STATE | container '$WINDOWS_CONTAINER': $CSTATE"
case "$STATE" in
  WINDOWS) summary; log "Windows is already running with the GPU. Nothing to do. READY"; exit 0 ;;
  INCONSISTENT) die "inconsistent state ($STATE_REASON). Refusing to act. Run scripts/status.sh and see docs/troubleshooting.md" ;;
esac
case "$CSTATE" in
  exited|created|absent) ;;
  *) die "unexpected container state '$CSTATE' - manual diagnosis needed (docker ps -a; docker logs $WINDOWS_CONTAINER)" ;;
esac

if [ "$CSTATE" = absent ]; then
  [ -n "$WINDOWS_COMPOSE" ] || die "container '$WINDOWS_CONTAINER' does not exist and WINDOWS_COMPOSE is not set (config/gpu.env)"
  [ -f "$WINDOWS_COMPOSE" ] || die "compose file not found: $WINDOWS_COMPOSE"
else
  check_compose_label; CLABEL="$(container_compose_label)"
fi

if [ $DRY = 1 ]; then
  log "dry-run plan (nothing is changed):"
  if [ "$STATE" = LINUX ]; then log "  1. gpu-to-vfio.sh: Linux -> VFIO (GPU $GPU_PCI, audio $GPU_AUDIO_PCI, group $VFIO_GROUP)"
  else log "  1. GPU already parked on VFIO: no transition"; fi
  log "  2. verify both functions on vfio-pci and $(vfio_node) present"
  if [ "$CSTATE" = absent ]; then log "  3. create container: docker compose -f $WINDOWS_COMPOSE up -d --no-recreate"
  else log "  3. docker start $WINDOWS_CONTAINER (existing container; compose label: ${CLABEL:-none})"; fi
  log "  4. wait for container running + QEMU referencing the GPU"
  [ "$STATE" != LINUX ] || "$DIR/gpu-to-vfio.sh" --check
  exit 0
fi

refuse_if_mocked   # everything below modifies the system
if [ "$STATE" = LINUX ]; then
  "$DIR/gpu-to-vfio.sh" || die "Linux -> VFIO failed; Windows NOT started"
  detect_state
fi
[ "$STATE" = VFIO_PARKED ] || die "expected VFIO_PARKED before starting Windows, got $STATE ($STATE_REASON)"
[ "$(pci_driver "$GPU_PCI")" = vfio-pci ] || die "$GPU_PCI is not on vfio-pci; Windows NOT started"
[ "$(pci_driver "$GPU_AUDIO_PCI")" = vfio-pci ] || die "$GPU_AUDIO_PCI is not on vfio-pci; Windows NOT started"
[ -e "$(vfio_node)" ] || die "$(vfio_node) is missing; Windows NOT started"
log "VFIO verified: $GPU_PCI + $GPU_AUDIO_PCI on vfio-pci, $(vfio_node) present"

# From here the GPU is on VFIO: any failure leaves it parked (no automatic rollback) and says so.
PARKED_NOTE=1
on_exit() {
  local rc=$?
  if [ $rc -ne 0 ] && [ "${PARKED_NOTE:-0}" = 1 ]; then
    echo >&2
    echo "!!! Windows did not start correctly. The GPU is CURRENTLY PARKED ON VFIO." >&2
    echo "!!! No automatic rollback. To give it back to Linux (after Windows is stopped): $DIR/stop-windows.sh" >&2
  fi
}
trap on_exit EXIT

if [ "$CSTATE" = absent ]; then
  log "container does not exist: creating it from $WINDOWS_COMPOSE (--no-recreate)"
  SERVICE="$(compose_service)"
  compose up -d --no-recreate "$SERVICE"
  find_container || true
else
  log "starting existing container '$WINDOWS_CONTAINER' with docker start"
  docker start "$WINDOWS_CONTAINER" >/dev/null
fi

up() { container_running && [ -n "$(qemu_full_pids)" ]; }
wait_until 60 up || die "container not running or QEMU not referencing the GPU after 60s (docker logs $WINDOWS_CONTAINER)"
sleep 3
up || die "Windows stopped right after starting (docker logs $WINDOWS_CONTAINER)"
PARKED_NOTE=0
summary
echo
log "READY: Windows is running with the GPU (QEMU owns IOMMU group $VFIO_GROUP). Connect with Moonlight."
