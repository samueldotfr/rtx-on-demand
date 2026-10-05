#!/usr/bin/env bash
# Read-only status. Changes nothing. Works without root (some details need root).
#   scripts/status.sh
# Exit code: 0 = known state, 2 = inconsistent.
set -Eeuo pipefail
HGW_TAG=status
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

if command -v docker >/dev/null 2>&1 && docker inspect "$WINDOWS_CONTAINER" >/dev/null 2>&1; then
  if container_running; then WIN=running; else WIN=stopped; fi
elif command -v docker >/dev/null 2>&1; then WIN="stopped (container not created, or no docker permission)"
else WIN="unknown (docker not found)"; fi

detect_state
QEMU=inactive; [ -n "$(qemu_pids gpu)" ] && QEMU=active

echo "Homelab GPU Workstation"
echo "-----------------------"
echo "GPU: $(gpu_name)"
echo "GPU driver: $(pci_driver "$GPU_PCI")"
echo "Audio driver: $(pci_driver "$GPU_AUDIO_PCI")"
echo "VFIO group: $VFIO_GROUP"
echo "Windows: $WIN"
echo "QEMU passthrough: $QEMU"
echo "State: $STATE"
[ -z "$STATE_REASON" ] || echo "Reason: $STATE_REASON"
if [ "$(pci_driver "$GPU_PCI")" = "$GPU_LINUX_DRIVER" ] && command -v nvidia-smi >/dev/null 2>&1; then
  if timeout 15 nvidia-smi -L >/dev/null 2>&1; then echo "NVIDIA: available"; else echo "NVIDIA: driver bound but nvidia-smi failed"; fi
else
  echo "NVIDIA: not available (GPU not owned by Linux)"
fi
[ "$STATE" != INCONSISTENT ] || exit 2
