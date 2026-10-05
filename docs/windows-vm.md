# Windows VM (dockur/windows)

[`dockurr/windows`](https://github.com/dockur/windows) runs Windows inside QEMU/KVM in a container
and can download the ISO and automate installation. **Dockur-specific:** variable names below are
its own. Check its README for the current list.

Use [examples/docker-compose.yml](../examples/docker-compose.yml) with a `.env` based on
[examples/.env.example](../examples/.env.example).

## What the example configures

| Item | Setting | Why |
|---|---|---|
| KVM | `/dev/kvm` mapped | Hardware virtualization |
| Machine | q35 + UEFI (dockur default for Windows 11) | PCIe topology needed for passthrough; Win11 needs UEFI |
| CPU | host passthrough (dockur default `CPU_MODEL=host`), `CPU_CORES`, optional `SMP`/`+topoext` | Reference: 12 vCPUs = 6 cores x 2 threads on an AMD host. `+topoext` is AMD-only |
| RAM | `RAM_SIZE` | VFIO pins all of it. Reference: 16 GB for the current build (an earlier install used 24 GB) |
| Disk | `DISK_SIZE`, sparse file in `./storage` | Reference: 512 GB |
| GPU | two `-device vfio-pci` in `ARGUMENTS` | GPU function with `multifunction=on` + audio function |
| Audio | `ich9-intel-hda` + `hda-output`, `-audiodev none` | [audio.md](audio.md) |
| Devices | `/dev/vfio/vfio`, `/dev/vfio/<group>`, `/dev/net/tun` | |
| Capabilities | `NET_ADMIN`, `IPC_LOCK`, memlock unlimited | VFIO pins memory |
| Ports | published on a LAN IP only | [security.md](security.md) |
| Restart | `"no"` | On-demand. An auto-restart could start QEMU before VFIO is ready |
| Stop | `stop_grace_period: 2m` | Clean Windows shutdown |

## First install: do it WITHOUT the GPU

Our workflow: install Windows with the GPU **still on Linux** (compose without the VFIO
`ARGUMENTS`/`devices`), complete setup via the dockur web console (noVNC, port 8006), install the NVIDIA
driver inside Windows, then switch to the passthrough compose. The reference build did its
initial install this way. Alternatively install with passthrough from the start (untested here).

## Inside Windows

1. NVIDIA driver (from NVIDIA, inside the guest). The GPU appears in Device Manager.
2. [Virtual Display Driver](virtual-display.md) + [Sunshine](sunshine.md) + [gamepad driver](gamepad.md).
3. OpenSSH Server / RDP are optional conveniences; see [security.md](security.md).

## Notes

- `./storage` contains the disk, firmware variables and identifiers. Back it up; never commit it.
- Re-creating the VM changes its SSH host key: remove the stale client entry (`ssh-keygen -R <host>`).
- Boot with the GPU already parked on VFIO: **use `scripts/start-windows.sh`**, not `docker compose up`.
