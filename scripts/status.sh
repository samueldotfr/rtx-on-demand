#!/usr/bin/env bash
# Read-only status. Changes nothing and never asks for sudo. Shows what it can see as a normal user.
#   scripts/status.sh
# Exit code: 0 = known state, 2 = inconsistent.
set -Eeuo pipefail
HGW_TAG=status
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

NOTES=()
if ! command -v docker >/dev/null 2>&1; then WIN="unknown (docker not found)"; NOTES+=("docker not installed")
elif ! docker_ok; then WIN="unknown (no permission to talk to docker)"; NOTES+=("run as root or add your user to the docker group to see the Windows container")
elif find_container; then WIN="$(container_state)"
else WIN="not found"; NOTES+=("$FIND_ERR"); fi

detect_state
QEMU=inactive; [ -n "$(qemu_pids gpu)" ] && QEMU=active
if [ "$(id -u)" != 0 ]; then NOTES+=("not root: processes of other users holding $(vfio_node) cannot be seen"); fi

echo "Homelab GPU Workstation"
echo "-----------------------"
echo "GPU: $(gpu_name) ($GPU_PCI, audio $GPU_AUDIO_PCI)"
echo "GPU driver: $(pci_driver "$GPU_PCI")"
echo "Audio driver: $(pci_driver "$GPU_AUDIO_PCI")"
echo "VFIO group: $VFIO_GROUP"
echo "Windows: $WIN${WINDOWS_CONTAINER:+ (container: $WINDOWS_CONTAINER)}"
echo "QEMU passthrough: $QEMU"
echo "State: $STATE"
[ -z "$STATE_REASON" ] || echo "Reason: $STATE_REASON"
if [ "$(pci_driver "$GPU_PCI")" = "$GPU_LINUX_DRIVER" ] && command -v nvidia-smi >/dev/null 2>&1; then
  if timeout 15 nvidia-smi -L >/dev/null 2>&1; then echo "NVIDIA: available"; else echo "NVIDIA: driver bound but nvidia-smi failed"; fi
else
  echo "NVIDIA: not available (GPU not owned by Linux)"
fi
for n in "${NOTES[@]}"; do echo "Note: $n"; done
[ "$STATE" != INCONSISTENT ] || exit 2
