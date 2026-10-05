#!/usr/bin/env bash
# Shared helpers for homelab-gpu-workstation scripts. Source this file, do not execute it.
# shellcheck shell=bash

HGW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test hook: HGW_FAKE_SYSFS points at a fake /sys tree so discovery and status logic can be tested
# without hardware. Every script that MODIFIES anything refuses to run while it is set.
SYSROOT="${HGW_FAKE_SYSFS:-/sys}"
PROC_DIR="${HGW_FAKE_PROC:-/proc}"      # same idea for /proc (process scans)
PCI_DIR="$SYSROOT/bus/pci/devices"
IOMMU_DIR="$SYSROOT/kernel/iommu_groups"

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

refuse_if_mocked() {
  [ -z "${HGW_FAKE_SYSFS:-}${HGW_FAKE_PROC:-}" ] || die "HGW_FAKE_SYSFS/HGW_FAKE_PROC is set (test mode): refusing to modify anything"
}

# ---- privileges ---------------------------------------------------------------
# ensure_root "$@": call from the top level of a script that must run as root, passing the script's
# own arguments. Re-executes the SAME script through sudo. No loop is possible: the test is the EUID,
# and HGW_REEXEC catches a sudo that "succeeds" without actually giving root.
ensure_root() {
  [ "$(id -u)" = 0 ] && return 0
  [ -z "${HGW_REEXEC:-}" ] || die "still not root after sudo; refusing to loop"
  command -v sudo >/dev/null 2>&1 || die "root is required and sudo was not found; re-run as root"
  local self envs=("HGW_REEXEC=1")
  self="$(readlink -f "${BASH_SOURCE[1]}")"
  [ -z "${HGW_CONFIG:-}" ] || envs+=("HGW_CONFIG=$HGW_CONFIG")
  log "root is required for this operation; re-running with sudo"
  exec sudo "${envs[@]}" "$self" "$@"
}

# ---- configuration --------------------------------------------------------------
# config/gpu.env is OPTIONAL. Every value below is auto-discovered unless overridden there.
# The only value that cannot be discovered is the Windows compose file, and only when the Windows
# container does not exist yet (an existing container carries its compose path in Docker labels).
load_config() {
  local cfg="${HGW_CONFIG:-}"
  if [ -n "$cfg" ]; then
    [ -r "$cfg" ] || die "HGW_CONFIG points to an unreadable file: $cfg"
  elif [ -r "$HGW_ROOT/config/gpu.env" ]; then cfg="$HGW_ROOT/config/gpu.env"; fi
  # shellcheck disable=SC1090
  [ -z "$cfg" ] || . "$cfg"
  GPU_PCI="${GPU_PCI:-}"
  GPU_AUDIO_PCI="${GPU_AUDIO_PCI:-}"
  VFIO_GROUP="${VFIO_GROUP:-auto}"
  GPU_LINUX_DRIVER="${GPU_LINUX_DRIVER:-nvidia}"
  AUDIO_LINUX_DRIVER="${AUDIO_LINUX_DRIVER:-snd_hda_intel}"
  WINDOWS_CONTAINER="${WINDOWS_CONTAINER:-}"
  WINDOWS_COMPOSE="${WINDOWS_COMPOSE:-}"
  WINDOWS_SERVICE="${WINDOWS_SERVICE:-}"
  PERSISTENCED_UNIT="${PERSISTENCED_UNIT-nvidia-persistenced}"
  LOCK_FILE="${LOCK_FILE:-/run/hgw-gpu-transition.lock}"
  UNBIND_TIMEOUT="${UNBIND_TIMEOUT:-30}"
  STOP_TIMEOUT="${STOP_TIMEOUT:-180}"
  VFIO_RELEASE_WAIT="${VFIO_RELEASE_WAIT:-30}"
  NVIDIA_RETURN_WAIT="${NVIDIA_RETURN_WAIT:-30}"
  CDI_MODE="${CDI_MODE:-auto}"          # auto | off | on
  CDI_SPEC_PATH="${CDI_SPEC_PATH:-/etc/cdi/nvidia.yaml}"
  case "$GPU_PCI$GPU_AUDIO_PCI" in *[!0-9a-fA-F:.]*) die "invalid PCI address in config" ;; esac
  discover_gpu
  discover_audio
  resolve_group
}

# ---- sysfs helpers (read-only) ---------------------------------------------
pci_driver()   { local l; l="$(readlink "$PCI_DIR/$1/driver" 2>/dev/null)" || true; echo "${l##*/}"; }
pci_override() { cat "$PCI_DIR/$1/driver_override" 2>/dev/null || echo "?"; }
pci_group()    { local l; l="$(readlink "$PCI_DIR/$1/iommu_group" 2>/dev/null)" || true; echo "${l##*/}"; }
pci_attr()     { cat "$PCI_DIR/$1/$2" 2>/dev/null || true; }

print_pci_state() {
  echo "  $GPU_PCI driver=$(pci_driver "$GPU_PCI") override=$(pci_override "$GPU_PCI")"
  echo "  $GPU_AUDIO_PCI driver=$(pci_driver "$GPU_AUDIO_PCI") override=$(pci_override "$GPU_AUDIO_PCI")"
}

gpu_name() {
  local n=""
  command -v lspci >/dev/null 2>&1 && n="$(lspci -s "${GPU_PCI#0000:}" 2>/dev/null | sed 's/^[^ ]* [^:]*: //; s/ (rev .*//')"
  echo "${n:-unknown}"
}

# GPU = the NVIDIA (vendor 0x10de) display-class (0x03xx) device. Exactly one, or an explicit GPU_PCI.
discover_gpu() {
  local d v c found=()
  if [ -n "$GPU_PCI" ]; then
    [ -d "$PCI_DIR/$GPU_PCI" ] || die "GPU_PCI=$GPU_PCI from config does not exist"
    return 0
  fi
  for d in "$PCI_DIR"/*; do
    v="$(pci_attr "${d##*/}" vendor)"; c="$(pci_attr "${d##*/}" class)"
    [ "$v" = 0x10de ] || continue
    case "$c" in 0x03*) found+=("${d##*/}") ;; esac
  done
  case "${#found[@]}" in
    1) GPU_PCI="${found[0]}" ;;
    0) die "no NVIDIA GPU found on the PCI bus. If your GPU is not NVIDIA, set GPU_PCI and GPU_AUDIO_PCI in config/gpu.env (untested)" ;;
    *) die "several NVIDIA GPUs found (${found[*]}); cannot know which to use. Set GPU_PCI (and GPU_AUDIO_PCI) in config/gpu.env" ;;
  esac
}

# Audio function = the NVIDIA audio-class (0x0403) function in the same slot as the GPU. Exactly one.
discover_audio() {
  local slot d found=()
  [ -z "$GPU_AUDIO_PCI" ] || { [ -d "$PCI_DIR/$GPU_AUDIO_PCI" ] || die "GPU_AUDIO_PCI=$GPU_AUDIO_PCI from config does not exist"; return 0; }
  slot="${GPU_PCI%.*}"
  for d in "$PCI_DIR/$slot".*; do
    [ -e "$d" ] || continue
    [ "${d##*/}" != "$GPU_PCI" ] || continue
    [ "$(pci_attr "${d##*/}" vendor)" = 0x10de ] || continue
    case "$(pci_attr "${d##*/}" class)" in 0x0403*) found+=("${d##*/}") ;; esac
  done
  case "${#found[@]}" in
    1) GPU_AUDIO_PCI="${found[0]}" ;;
    0) die "no NVIDIA audio function found next to $GPU_PCI. Set GPU_AUDIO_PCI in config/gpu.env" ;;
    *) die "several audio functions next to $GPU_PCI (${found[*]}); set GPU_AUDIO_PCI in config/gpu.env" ;;
  esac
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
  n="$(find "$IOMMU_DIR/$VFIO_GROUP/devices" -mindepth 1 -maxdepth 1 | wc -l)"
  if [ "$n" != 2 ] && [ "${ALLOW_SHARED_GROUP:-0}" != 1 ]; then
    die "IOMMU group $VFIO_GROUP has $n devices (expected exactly the 2 GPU functions). Set ALLOW_SHARED_GROUP=1 only if you understand docs/iommu-and-vfio.md"
  fi
}

# ---- docker / qemu ----------------------------------------------------------
docker_ok() { command -v docker >/dev/null 2>&1 && docker ps -q >/dev/null 2>&1; }
need_docker() { docker_ok || die "cannot talk to docker (not installed, daemon down, or no permission)"; }

container_state() { # running | exited | created | paused | ... | absent
  [ -n "$WINDOWS_CONTAINER" ] || { echo absent; return 0; }
  docker inspect -f '{{.State.Status}}' "$WINDOWS_CONTAINER" 2>/dev/null || echo absent
}
container_running() { [ "$(container_state)" = running ]; }
container_label() { docker inspect -f "{{index .Config.Labels \"$1\"}}" "$WINDOWS_CONTAINER" 2>/dev/null || true; }

# Sets WINDOWS_CONTAINER (config override > the single dockurr/windows container > container_name in the compose file).
# Returns 1 with FIND_ERR set when it cannot decide (callers choose to die or to report).
find_container() {
  local names=() n
  FIND_ERR=""
  [ -z "$WINDOWS_CONTAINER" ] || return 0
  mapfile -t names < <(docker ps -a --filter ancestor=dockurr/windows --format '{{.Names}}' 2>/dev/null)
  case "${#names[@]}" in
    1) WINDOWS_CONTAINER="${names[0]}"; return 0 ;;
    0) ;;
    *) FIND_ERR="several dockurr/windows containers (${names[*]}); set WINDOWS_CONTAINER in config/gpu.env"; return 1 ;;
  esac
  if [ -n "$WINDOWS_COMPOSE" ] && [ -r "$WINDOWS_COMPOSE" ]; then
    mapfile -t names < <(sed -n 's/^[[:space:]]*container_name:[[:space:]]*["'\'']\{0,1\}\([A-Za-z0-9_.-]*\).*/\1/p' "$WINDOWS_COMPOSE")
    if [ "${#names[@]}" = 1 ] && [ -n "${names[0]}" ]; then WINDOWS_CONTAINER="${names[0]}"; return 0; fi
    FIND_ERR="cannot read a single container_name from $WINDOWS_COMPOSE; set WINDOWS_CONTAINER in config/gpu.env"; return 1
  fi
  n="no Windows container found"
  FIND_ERR="$n. Create it first, or set WINDOWS_COMPOSE=/path/to/docker-compose.yml in config/gpu.env"
  return 1
}
require_container() { find_container || die "$FIND_ERR"; }

compose_realpath() { readlink -f "$1" 2>/dev/null || echo "$1"; }

# Compose file label of an existing container (empty if none).
container_compose_label() { container_label com.docker.compose.project.config_files; }

# Check an existing container was created from the configured compose file (only if one is configured).
check_compose_label() {
  local label want f ok=1
  [ -n "$WINDOWS_COMPOSE" ] || return 0
  label="$(container_compose_label)"
  [ -n "$label" ] || die "container '$WINDOWS_CONTAINER' has no compose label but WINDOWS_COMPOSE is configured; refusing"
  want="$(compose_realpath "$WINDOWS_COMPOSE")"
  local IFS=,
  for f in $label; do [ "$(compose_realpath "$f")" = "$want" ] && ok=0; done
  [ $ok = 0 ] || die "container '$WINDOWS_CONTAINER' was not created from $WINDOWS_COMPOSE (label: $label); refusing"
}

compose() {
  [ -n "$WINDOWS_COMPOSE" ] || die "WINDOWS_COMPOSE is not set (needed only to create the container)"
  [ -f "$WINDOWS_COMPOSE" ] || die "compose file not found: $WINDOWS_COMPOSE"
  docker compose -f "$WINDOWS_COMPOSE" "$@"
}

# Service to create: config override > single service in the compose file.
compose_service() {
  local s=()
  [ -z "$WINDOWS_SERVICE" ] || { echo "$WINDOWS_SERVICE"; return 0; }
  mapfile -t s < <(compose config --services 2>/dev/null)
  [ "${#s[@]}" = 1 ] || die "compose file defines ${#s[@]} services; set WINDOWS_SERVICE in config/gpu.env"
  echo "${s[0]}"
}

# Prints PIDs of qemu-system processes. Modes:
#   any  - every qemu-system process
#   gpu  - those referencing the GPU OR its audio function (orphan / guard checks)
#   full - those referencing BOTH functions (passthrough confirmed)
# A process that exits between listing and reading is ignored (normal race). A process that still
# exists but whose cmdline cannot be read is reported as "unreadable:<pid>" (never silently dropped),
# so callers treat it as "a QEMU may be present" and fail closed. These PIDs are only used for
# decisions, never for signalling.
qemu_pids() {
  local mode="${1:-any}" f pid c
  for f in "$PROC_DIR"/[0-9]*/cmdline; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    pid="${f#"$PROC_DIR"/}"; pid="${pid%%/*}"
    if ! c="$({ tr '\0' ' ' < "$f"; } 2>/dev/null)"; then
      [ -d "$PROC_DIR/$pid" ] || continue
      warn "cannot read $f although the process exists; cannot rule out a QEMU process"
      echo "unreadable:$pid"; continue
    fi
    case "$c" in qemu-system*) ;; *) continue ;; esac
    case "$mode" in
      gpu)  qemu_refs "$c" "$GPU_PCI" || qemu_refs "$c" "$GPU_AUDIO_PCI" || continue ;;
      full) qemu_refs "$c" "$GPU_PCI" && qemu_refs "$c" "$GPU_AUDIO_PCI" || continue ;;
    esac
    echo "$pid"
  done
}
qemu_refs() { case "$1" in *"host=$2 "*|*"host=$2,"*) return 0 ;; *) return 1 ;; esac; }   # $1 = cmdline with NULs as spaces
qemu_full_pids() { qemu_pids full | grep -v '^unreadable:' || true; }

vfio_node() { echo "/dev/vfio/$VFIO_GROUP"; }

# 0 if some process holds the VFIO group node. Without root, other users' holders are invisible.
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
  for n in "$PCI_DIR/$GPU_PCI"/drm/card* "$PCI_DIR/$GPU_PCI"/drm/renderD*; do
    [ -e "$n" ] && nodes+=("/dev/dri/${n##*/}")
  done
  [ "${#nodes[@]}" -gt 0 ] || return 0
  for n in "${nodes[@]}"; do
    [ -e "$n" ] || continue
    for pid in $(fuser "$n" 2>/dev/null); do
      pid="${pid//[!0-9]/}"; [ -n "$pid" ] || continue
      case "$seen" in *" $pid "*) continue ;; esac
      seen="$seen$pid "
      comm="$(cat "$PROC_DIR/$pid/comm" 2>/dev/null)" || { [ -d "$PROC_DIR/$pid" ] || continue; comm='?'; }   # vanished pid: ignore
      case "$comm" in nvidia-persiste*) continue ;; esac
      echo "$pid:$comm"
    done
  done
}

# ---- state machine ----------------------------------------------------------
# Sets STATE in {LINUX, VFIO_PARKED, WINDOWS, INCONSISTENT} and STATE_REASON (read by the callers).
# shellcheck disable=SC2034
detect_state() {
  local gd ad win=0 qemu=0 qfull=0
  gd="$(pci_driver "$GPU_PCI")"; ad="$(pci_driver "$GPU_AUDIO_PCI")"
  container_running && win=1
  [ -n "$(qemu_pids gpu)" ] && qemu=1
  [ -n "$(qemu_full_pids)" ] && qfull=1
  STATE=INCONSISTENT; STATE_REASON="drivers: GPU='${gd:-none}' audio='${ad:-none}'"
  if [ "$gd" = "$GPU_LINUX_DRIVER" ] && [ "$ad" = "$AUDIO_LINUX_DRIVER" ]; then
    if [ $win = 1 ] || [ $qemu = 1 ]; then
      STATE_REASON="Windows/QEMU is running while the GPU is bound to Linux drivers"
    else STATE=LINUX; STATE_REASON=""; fi
  elif [ "$gd" = vfio-pci ] && [ "$ad" = vfio-pci ]; then
    if [ $win = 1 ] && [ $qfull = 1 ]; then STATE=WINDOWS; STATE_REASON=""
    elif [ $win = 1 ] && [ $qemu = 1 ]; then STATE_REASON="QEMU does not reference BOTH the GPU and its audio function (or a QEMU cmdline is unreadable)"
    elif [ $win = 1 ]; then STATE_REASON="Windows container running but no QEMU references the GPU"
    elif [ $qemu = 1 ]; then STATE_REASON="QEMU references the GPU but the Windows container is not running"
    elif vfio_group_held; then STATE_REASON="$(vfio_node) is held by an unknown process"
    else STATE=VFIO_PARKED; STATE_REASON=""; fi
  fi
}

# ---- locking ------------------------------------------------------------------
acquire_lock() {
  exec 9>"$LOCK_FILE" || die "cannot open lock file $LOCK_FILE"
  flock -n 9 || die "another GPU transition is in progress (lock: $LOCK_FILE)"
}

wait_until() { # wait_until <seconds> <command...>
  local t="$1" i=0; shift
  while [ "$i" -lt "$t" ]; do "$@" && return 0; sleep 1; i=$((i+1)); done
  "$@"
}
