#!/usr/bin/env bash
# Shared helpers for homelab-gpu-workstation scripts. Source this file, do not execute it.
# shellcheck shell=bash

HGW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()  { printf '[%s] %s\n' "${HGW_TAG:-hgw}" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "${HGW_TAG:-hgw}" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "${HGW_TAG:-hgw}" "$*" >&2; exit 1; }

# fail_state: print the current GPU state and exit. Never rolls back (fail closed):
# an unknown state is left for a human to inspect.
fail_state() {
  printf '[%s] FAILED: %s\n' "${HGW_TAG:-hgw}" "$*" >&2
  print_pci_state >&2 || true
  echo "  No automatic rollback was attempted. Inspect with scripts/status.sh." >&2
  exit 1
}

load_config() {
  local cfg="${HGW_CONFIG:-$HGW_ROOT/config/gpu.env}"
  [ -r "$cfg" ] || die "config not found: $cfg (copy config/gpu.env.example to config/gpu.env and edit it)"
  # shellcheck disable=SC1090
  . "$cfg"
  : "${GPU_PCI:?GPU_PCI is not set in $cfg}"
  : "${GPU_AUDIO_PCI:?GPU_AUDIO_PCI is not set in $cfg}"
  VFIO_GROUP="${VFIO_GROUP:-auto}"
  EXPECT_GPU_ID="${EXPECT_GPU_ID:-}"
  EXPECT_AUDIO_ID="${EXPECT_AUDIO_ID:-}"
  GPU_LINUX_DRIVER="${GPU_LINUX_DRIVER:-nvidia}"
  AUDIO_LINUX_DRIVER="${AUDIO_LINUX_DRIVER:-snd_hda_intel}"
  WINDOWS_CONTAINER="${WINDOWS_CONTAINER:-windows}"
  WINDOWS_COMPOSE_DIR="${WINDOWS_COMPOSE_DIR:-}"
  WINDOWS_COMPOSE_FILE="${WINDOWS_COMPOSE_FILE:-docker-compose.yml}"
  WINDOWS_SERVICE="${WINDOWS_SERVICE:-windows}"
  PERSISTENCED_UNIT="${PERSISTENCED_UNIT:-nvidia-persistenced}"
  LOCK_FILE="${LOCK_FILE:-/run/hgw-gpu-transition.lock}"
  UNBIND_TIMEOUT="${UNBIND_TIMEOUT:-30}"
  STOP_TIMEOUT="${STOP_TIMEOUT:-180}"
  VFIO_RELEASE_WAIT="${VFIO_RELEASE_WAIT:-30}"
  NVIDIA_RETURN_WAIT="${NVIDIA_RETURN_WAIT:-30}"
  CDI_MODE="${CDI_MODE:-auto}"          # auto | off | on
  CDI_SPEC_PATH="${CDI_SPEC_PATH:-/etc/cdi/nvidia.yaml}"
  case "$GPU_PCI$GPU_AUDIO_PCI" in *[!0-9a-fA-F:.]*) die "invalid PCI address in config" ;; esac
  [ -d "/sys/bus/pci/devices/$GPU_PCI" ] || die "PCI device $GPU_PCI not found"
  [ -d "/sys/bus/pci/devices/$GPU_AUDIO_PCI" ] || die "PCI device $GPU_AUDIO_PCI not found"
  resolve_group
}

# ---- sysfs helpers (read-only) ---------------------------------------------
pci_driver()   { local l; l="$(readlink "/sys/bus/pci/devices/$1/driver" 2>/dev/null)" || true; echo "${l##*/}"; }
pci_override() { cat "/sys/bus/pci/devices/$1/driver_override" 2>/dev/null || echo "?"; }
pci_group()    { local l; l="$(readlink "/sys/bus/pci/devices/$1/iommu_group" 2>/dev/null)" || true; echo "${l##*/}"; }
pci_ids()      { echo "$(cat "/sys/bus/pci/devices/$1/vendor"):$(cat "/sys/bus/pci/devices/$1/device")" | sed 's/0x//g'; }

print_pci_state() {
  echo "  $GPU_PCI driver=$(pci_driver "$GPU_PCI") override=$(pci_override "$GPU_PCI")"
  echo "  $GPU_AUDIO_PCI driver=$(pci_driver "$GPU_AUDIO_PCI") override=$(pci_override "$GPU_AUDIO_PCI")"
}

gpu_name() {
  local n=""
  command -v lspci >/dev/null 2>&1 && n="$(lspci -s "${GPU_PCI#0000:}" 2>/dev/null | sed 's/^[^ ]* [^:]*: //; s/ (rev .*//')"
  echo "${n:-unknown}"
}

# Sets VFIO_GROUP to the real IOMMU group and checks it only contains the GPU functions.
resolve_group() {
  local g1 g2 n
  g1="$(pci_group "$GPU_PCI")"; g2="$(pci_group "$GPU_AUDIO_PCI")"
  [ -n "$g1" ] || die "no IOMMU group for $GPU_PCI (is the IOMMU enabled? see docs/iommu-and-vfio.md)"
  [ "$g1" = "$g2" ] || die "GPU and audio function are in different IOMMU groups ($g1 / $g2); this tool does not support that layout"
  if [ "$VFIO_GROUP" != auto ] && [ "$VFIO_GROUP" != "$g1" ]; then
    die "VFIO_GROUP=$VFIO_GROUP in config but the device is in IOMMU group $g1"
  fi
  VFIO_GROUP="$g1"
  n="$(find "/sys/kernel/iommu_groups/$VFIO_GROUP/devices" -mindepth 1 -maxdepth 1 | wc -l)"
  if [ "$n" != 2 ] && [ "${ALLOW_SHARED_GROUP:-0}" != 1 ]; then
    die "IOMMU group $VFIO_GROUP has $n devices (expected exactly the 2 GPU functions). Set ALLOW_SHARED_GROUP=1 only if you understand docs/iommu-and-vfio.md"
  fi
}

check_device_ids() {
  [ -z "$EXPECT_GPU_ID" ]   || [ "$(pci_ids "$GPU_PCI")" = "$EXPECT_GPU_ID" ]         || return 1
  [ -z "$EXPECT_AUDIO_ID" ] || [ "$(pci_ids "$GPU_AUDIO_PCI")" = "$EXPECT_AUDIO_ID" ] || return 1
}

# ---- docker / qemu ----------------------------------------------------------
need_docker() { command -v docker >/dev/null 2>&1 || die "docker not found"; }

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$WINDOWS_CONTAINER" 2>/dev/null)" = true ]
}

compose() {
  [ -n "$WINDOWS_COMPOSE_DIR" ] || die "WINDOWS_COMPOSE_DIR is not set in config"
  [ -f "$WINDOWS_COMPOSE_DIR/$WINDOWS_COMPOSE_FILE" ] || die "compose file not found: $WINDOWS_COMPOSE_DIR/$WINDOWS_COMPOSE_FILE"
  ( cd "$WINDOWS_COMPOSE_DIR" && docker compose -f "$WINDOWS_COMPOSE_FILE" "$@" )
}

# Prints PIDs of qemu-system processes. Mode "gpu" keeps only those referencing the GPU.
qemu_pids() {
  local f pid c
  for f in /proc/[0-9]*/cmdline; do
    pid="${f#/proc/}"; pid="${pid%%/*}"
    c="$(tr '\0' ' ' < "$f" 2>/dev/null)" || continue
    case "$c" in qemu-system*) ;; *) continue ;; esac
    if [ "${1:-any}" = gpu ]; then
      case "$c" in *"host=$GPU_PCI"*) ;; *) continue ;; esac
    fi
    echo "$pid"
  done
}

vfio_node() { echo "/dev/vfio/$VFIO_GROUP"; }

# 0 if some process holds the VFIO group node.
vfio_group_held() {
  [ -e "$(vfio_node)" ] || return 1
  command -v fuser >/dev/null 2>&1 || die "fuser not found (install psmisc)"
  fuser "$(vfio_node)" >/dev/null 2>&1
}

# Prints "pid:comm" for processes holding NVIDIA / DRM nodes of THIS GPU (ignores persistenced).
gpu_node_holders() {
  local n pid comm seen=" "
  local nodes=()
  for n in /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-uvm-tools /dev/nvidia-modeset; do
    [ -e "$n" ] && nodes+=("$n")
  done
  for n in "/sys/bus/pci/devices/$GPU_PCI"/drm/card* "/sys/bus/pci/devices/$GPU_PCI"/drm/renderD*; do
    [ -e "$n" ] && nodes+=("/dev/dri/${n##*/}")
  done
  [ "${#nodes[@]}" -gt 0 ] || return 0
  for n in "${nodes[@]}"; do
    [ -e "$n" ] || continue
    for pid in $(fuser "$n" 2>/dev/null); do
      pid="${pid//[!0-9]/}"; [ -n "$pid" ] || continue
      case "$seen" in *" $pid "*) continue ;; esac
      seen="$seen$pid "
      comm="$(cat "/proc/$pid/comm" 2>/dev/null || echo '?')"
      case "$comm" in "$PERSISTENCED_UNIT"*|nvidia-persiste*) continue ;; esac
      echo "$pid:$comm"
    done
  done
}

# ---- state machine ----------------------------------------------------------
# Sets STATE in {LINUX, VFIO_PARKED, WINDOWS, INCONSISTENT} and STATE_REASON.
detect_state() {
  local gd ad win=0 qemu=0
  gd="$(pci_driver "$GPU_PCI")"; ad="$(pci_driver "$GPU_AUDIO_PCI")"
  container_running && win=1
  [ -n "$(qemu_pids gpu)" ] && qemu=1
  STATE=INCONSISTENT; STATE_REASON="drivers: GPU='${gd:-none}' audio='${ad:-none}'"
  if [ "$gd" = "$GPU_LINUX_DRIVER" ] && [ "$ad" = "$AUDIO_LINUX_DRIVER" ]; then
    if [ $win = 1 ] || [ $qemu = 1 ]; then
      STATE_REASON="Windows/QEMU is running while the GPU is bound to Linux drivers"
    else STATE=LINUX; STATE_REASON=""; fi
  elif [ "$gd" = vfio-pci ] && [ "$ad" = vfio-pci ]; then
    if [ $win = 1 ] && [ $qemu = 1 ]; then STATE=WINDOWS; STATE_REASON=""
    elif [ $win = 1 ]; then STATE_REASON="Windows container running but no QEMU references the GPU"
    elif [ $qemu = 1 ]; then STATE_REASON="QEMU references the GPU but the Windows container is not running"
    elif vfio_group_held; then STATE_REASON="$(vfio_node) is held by an unknown process"
    else STATE=VFIO_PARKED; STATE_REASON=""; fi
  fi
}

# ---- locking / privileges ---------------------------------------------------
require_root() { [ "$(id -u)" = 0 ] || die "run as root (sudo) - GPU rebinding and docker need it"; }

acquire_lock() {
  exec 9>"$LOCK_FILE" || die "cannot open lock file $LOCK_FILE"
  flock -n 9 || die "another GPU transition is in progress (lock: $LOCK_FILE)"
}

wait_until() { # wait_until <seconds> <command...>
  local t="$1" i=0; shift
  while [ "$i" -lt "$t" ]; do "$@" && return 0; sleep 1; i=$((i+1)); done
  "$@"
}
