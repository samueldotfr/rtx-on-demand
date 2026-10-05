# GPU handoff

How `scripts/` move the GPU. Each step names the script, the guard before it and the check after it.
Read [iommu-and-vfio.md](iommu-and-vfio.md) for the concepts.

## Linux → VFIO (`gpu-to-vfio.sh`)

1. Lock (`flock` on `LOCK_FILE`) so only one transition runs.
2. Guards: see iommu-and-vfio.md. `--check` runs them alone, read-only.
3. Stop `nvidia-persistenced`.
4. `modprobe vfio-pci`.
5. For each function: set `driver_override`, unbind (30 s timeout).
6. `drivers_probe`; wait for `vfio-pci`.
7. Post: both on `vfio-pci`; `/dev/vfio/<group>` exists.

Tip: processes that keep `/dev/nvidia*` open are the usual blocker (CUDA workloads, containers, monitoring agents, a desktop session on that GPU).
List them with `sudo fuser -v /dev/nvidia*`.

## Start Windows

Only from the VFIO-parked state. `start-windows.sh` does the transition above if needed, then starts Windows:

- container already running with the GPU → nothing to do (idempotent);
- container exists → `docker start` (it keeps the devices, arguments and volumes it was created with; if a compose file is
  configured, the container's compose label must match it or the script refuses);
- container does not exist → `docker compose up -d --no-recreate` with the configured compose file;
- any other container state (paused, restarting, dead...) → refuse.

It then waits until the container runs **and** a QEMU process references the GPU. If anything fails after the GPU was parked, it
says so and leaves it parked (no automatic rollback); `stop-windows.sh` returns it.

## Windows → Linux (`stop-windows.sh`, then `gpu-to-linux.sh`)

1. Root check first (so Windows is never stopped and *then* we discover missing privileges).
2. `docker stop -t STOP_TIMEOUT` (graceful ACPI shutdown).
3. Wait for the container and QEMU to disappear.
4. `gpu-to-linux.sh` waits for `/dev/vfio/<group>` to be released.
5. Unbind from `vfio-pci`, clear `driver_override`, `drivers_probe`.
6. Post: Linux drivers bound, override empty, `nvidia-persistenced` active, `nvidia-smi -L` works.
7. CDI: regenerate the spec atomically (temp file + `mv`) and check `nvidia.com/gpu=all` is listed. Skipped when `CDI_MODE=off`, or `auto` with no existing spec / no `nvidia-ctk`.

## Why CDI must be regenerated

The CDI spec names device nodes and may embed device identity. Docker/Podman use it to inject the GPU. If the spec is stale, containers can fail to start
or miss devices after a round trip. We did not measure exactly what breaks without regeneration; it is cheap, so the script does it.

## What is not handled

- A reboot or crash while in state B or C (the matrix is incomplete; see [known-issues.md](known-issues.md)).
- Host power management / reset quirks of other GPU models. NVIDIA RTX 40 series only was tested.
- Workloads on Linux are neither stopped nor started by these scripts. Stop them yourself; the guards will refuse otherwise.
