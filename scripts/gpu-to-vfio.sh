#!/usr/bin/env bash
# Linux -> VFIO: release the GPU from NVIDIA/snd_hda_intel and park it on vfio-pci.
#   scripts/gpu-to-vfio.sh --check   guards only, read-only, no root needed (results are
#                                    less complete without root: other users' processes are hidden)
#   scripts/gpu-to-vfio.sh           perform the transition (re-runs itself with sudo; NOT persistent across reboot)
# Does not start Windows. Does not touch GRUB/initramfs/modprobe config.
# On any failure it stops and prints the state. It never rolls back by itself.
set -Eeuo pipefail
HGW_TAG=gpu-to-vfio
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CHECK=0
case "${1:-}" in
  "") ;;
  --check) CHECK=1 ;;
  -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

if [ $CHECK = 0 ]; then refuse_if_mocked; ensure_root "$@"; fi
load_config
if [ $CHECK = 0 ]; then acquire_lock; else [ "$(id -u)" = 0 ] || warn "not root: guards are incomplete"; fi

guards() {
  log "guards (read-only)"
  [ "$(pci_driver "$GPU_PCI")" = "$GPU_LINUX_DRIVER" ] && [ "$(pci_driver "$GPU_AUDIO_PCI")" = "$AUDIO_LINUX_DRIVER" ] \
    || fail_state "GPU is not in the Linux state (expected $GPU_LINUX_DRIVER + $AUDIO_LINUX_DRIVER)"
  [ -z "$(qemu_pids gpu)" ] || fail_state "a QEMU process already references the GPU"
  ! vfio_group_held || fail_state "$(vfio_node) is already held"
  if command -v nvidia-smi >/dev/null 2>&1; then
    local apps
    apps="$(timeout 20 nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>&1)" \
      || fail_state "nvidia-smi failed, cannot verify that no compute process uses the GPU: ${apps%%$'\n'*}"
    [ -z "$apps" ] || fail_state "compute processes are using the GPU: $apps"
  fi
  local busy; busy="$(gpu_node_holders | tr '\n' ' ')"
  [ -z "$busy" ] || fail_state "processes hold GPU device nodes (pid:name): $busy- stop them first (docs/troubleshooting.md)"
  print_pci_state
  log "guards OK (IOMMU group $VFIO_GROUP)"
}

unbind_one() { # <pci>: set override, unbind with timeout
  local d="$1"
  echo vfio-pci > "/sys/bus/pci/devices/$d/driver_override"
  if [ -e "/sys/bus/pci/devices/$d/driver" ]; then
    timeout "$UNBIND_TIMEOUT" sh -c 'echo "$1" > "/sys/bus/pci/devices/$1/driver/unbind"' _ "$d" \
      || fail_state "unbind of $d failed or timed out"
  fi
}

guards
[ $CHECK = 1 ] && exit 0

T0=$(date +%s)
if [ -n "$PERSISTENCED_UNIT" ] && systemctl is-active --quiet "$PERSISTENCED_UNIT"; then
  log "stopping $PERSISTENCED_UNIT (it keeps /dev/nvidia* open)"
  systemctl stop "$PERSISTENCED_UNIT" || fail_state "could not stop $PERSISTENCED_UNIT"
  sleep 1
fi
modprobe vfio-pci || fail_state "modprobe vfio-pci"
log "unbinding and setting driver_override=vfio-pci"
unbind_one "$GPU_PCI"
unbind_one "$GPU_AUDIO_PCI"
print_pci_state
log "reprobing"
echo "$GPU_PCI" > /sys/bus/pci/drivers_probe
echo "$GPU_AUDIO_PCI" > /sys/bus/pci/drivers_probe
wait_until 10 test "$(pci_driver "$GPU_PCI")" = vfio-pci || true
print_pci_state
[ "$(pci_driver "$GPU_PCI")" = vfio-pci ] || fail_state "$GPU_PCI is not on vfio-pci"
[ "$(pci_driver "$GPU_AUDIO_PCI")" = vfio-pci ] || fail_state "$GPU_AUDIO_PCI is not on vfio-pci"
[ -e "$(vfio_node)" ] || fail_state "$(vfio_node) does not exist"
log "GPU PARKED ON VFIO in $(( $(date +%s)-T0 ))s - Windows has not been started."
