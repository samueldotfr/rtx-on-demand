#!/usr/bin/env bash
# VFIO -> Linux: return the GPU to the NVIDIA and audio drivers, then verify.
#   scripts/gpu-to-linux.sh --check   guards only (read-only)
#   scripts/gpu-to-linux.sh           perform the transition (re-runs itself with sudo)
# Refuses to run while the Windows container or any QEMU is alive or holds the VFIO group.
set -Eeuo pipefail
HGW_TAG=gpu-to-linux
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CHECK=0
case "${1:-}" in
  "") ;;
  --check) CHECK=1 ;;
  -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

if [ $CHECK = 0 ]; then refuse_if_mocked; ensure_root "$@"; fi
load_config
need_docker
find_container || warn "$FIND_ERR (assuming no Windows container; the QEMU and VFIO guards still apply)"
if [ $CHECK = 0 ]; then acquire_lock; fi

not_held() { ! vfio_group_held; }

guards() {
  log "guards (read-only)"
  ! container_running || fail_state "Windows container '$WINDOWS_CONTAINER' is still running"
  [ -z "$(qemu_pids any)" ] || fail_state "a qemu-system process is still running"
  wait_until "$VFIO_RELEASE_WAIT" not_held || fail_state "$(vfio_node) still held after ${VFIO_RELEASE_WAIT}s"
  [ "$(pci_driver "$GPU_PCI")" = vfio-pci ] && [ "$(pci_driver "$GPU_AUDIO_PCI")" = vfio-pci ] \
    || fail_state "GPU is not parked on vfio-pci; nothing to return (use scripts/status.sh)"
  print_pci_state
}

gpu_back() {
  [ "$(pci_driver "$GPU_PCI")" = "$GPU_LINUX_DRIVER" ] && [ "$(pci_driver "$GPU_AUDIO_PCI")" = "$AUDIO_LINUX_DRIVER" ]
}

regenerate_cdi() {
  case "$CDI_MODE" in
    off) log "CDI: disabled"; return 0 ;;
    auto) command -v nvidia-ctk >/dev/null 2>&1 && [ -e "$CDI_SPEC_PATH" ] || { log "CDI: not in use, skipped"; return 0; } ;;
    on) command -v nvidia-ctk >/dev/null 2>&1 || fail_state "CDI_MODE=on but nvidia-ctk is missing" ;;
    *) die "invalid CDI_MODE=$CDI_MODE" ;;
  esac
  local tmp; tmp="$(dirname "$CDI_SPEC_PATH")/.nvidia-cdi.tmp.yaml"   # same filesystem -> atomic mv
  nvidia-ctk cdi generate --output="$tmp" >/dev/null 2>&1 || { rm -f -- "$tmp"; fail_state "nvidia-ctk cdi generate failed"; }
  mv -- "$tmp" "$CDI_SPEC_PATH" || fail_state "could not install CDI spec"
  nvidia-ctk cdi list 2>/dev/null | grep -qx 'nvidia.com/gpu=all' || fail_state "CDI spec lacks nvidia.com/gpu=all"
  if [ -d /var/run/cdi ] && [ -e /var/run/cdi/nvidia.yaml ]; then   # some setups also read a copy from /var/run/cdi
    cp -- "$CDI_SPEC_PATH" /run/.nvidia-cdi-sync.tmp && mv -- /run/.nvidia-cdi-sync.tmp /var/run/cdi/nvidia.yaml \
      || fail_state "could not refresh /var/run/cdi/nvidia.yaml"
  fi
  log "CDI: spec regenerated"
}

guards
[ $CHECK = 1 ] && { log "guards OK"; exit 0; }

T0=$(date +%s)
log "unbinding vfio-pci and clearing driver_override"
for d in "$GPU_PCI" "$GPU_AUDIO_PCI"; do
  if [ -e "/sys/bus/pci/devices/$d/driver" ]; then
    # shellcheck disable=SC2016  # $1 is expanded by the inner sh on purpose (argument, not interpolation)
    timeout "$UNBIND_TIMEOUT" sh -c 'echo "$1" > "/sys/bus/pci/devices/$1/driver/unbind"' _ "$d" \
      || fail_state "unbind of $d failed or timed out"
  fi
  pci_clear_override "$d" || fail_state "could not write driver_override of $d"
done
# Verify BEFORE reprobing: with an override still set, the probe would just rebind vfio-pci.
for d in "$GPU_PCI" "$GPU_AUDIO_PCI"; do
  [ "$(pci_override "$d")" = "(null)" ] || fail_state "driver_override of $d is still '$(pci_override "$d")' after clearing; NOT reprobing"
done
log "reprobing"
echo "$GPU_PCI" > /sys/bus/pci/drivers_probe
echo "$GPU_AUDIO_PCI" > /sys/bus/pci/drivers_probe
lsmod | grep -q "^${GPU_LINUX_DRIVER} " || modprobe "$GPU_LINUX_DRIVER" || fail_state "modprobe $GPU_LINUX_DRIVER"
wait_until "$NVIDIA_RETURN_WAIT" gpu_back || fail_state "drivers did not come back (expected $GPU_LINUX_DRIVER + $AUDIO_LINUX_DRIVER)"
if [ -n "$PERSISTENCED_UNIT" ] && systemctl cat "$PERSISTENCED_UNIT" >/dev/null 2>&1; then
  systemctl start "$PERSISTENCED_UNIT" || fail_state "could not start $PERSISTENCED_UNIT"
  sleep 2
  systemctl is-active --quiet "$PERSISTENCED_UNIT" || fail_state "$PERSISTENCED_UNIT is not active"
fi
print_pci_state
command -v nvidia-smi >/dev/null 2>&1 || fail_state "nvidia-smi not found"
nvidia-smi -L || fail_state "nvidia-smi cannot see the GPU"
regenerate_cdi
log "READY FOR LINUX in $(( $(date +%s)-T0 ))s"
