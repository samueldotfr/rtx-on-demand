# Host setup (Ubuntu 24.04 reference)

Ubuntu-specific commands. Other distributions: the concepts transfer, the commands do not (untested).

## 1. BIOS/UEFI

- Enable IOMMU (AMD: "IOMMU"/"AMD-Vi"; Intel: "VT-d") and virtualization (SVM / VT-x).
- Leave the passthrough GPU as a secondary device; prefer iGPU for the host console if you have one.
- Resizable BAR / Above-4G decoding: leave at defaults unless you hit trouble (we did not tune this).

## 2. Kernel parameters

AMD hosts normally have the IOMMU on by default. Check first:

```bash
sudo dmesg | grep -i -E 'iommu|amd-vi|dmar'
ls /sys/kernel/iommu_groups | head
```

If empty, add `amd_iommu=on` (AMD) or `intel_iommu=on` (Intel) to `GRUB_CMDLINE_LINUX_DEFAULT`
in `/etc/default/grub`, run `sudo update-grub`, reboot. `iommu=pt` is a common addition for
performance; it was not required to make this project work on our reference build (untested as a variable).

You do **not** need `vfio-pci.ids=...` for this project. See [iommu-and-vfio.md](iommu-and-vfio.md).

## 3. NVIDIA driver (Linux side)

Install the driver from Ubuntu's `ubuntu-drivers` or NVIDIA's repository. Reference: NVIDIA
**open** kernel module flavor, 595.x series. Verify:

```bash
nvidia-smi
lspci -nnk -s 01:00     # adjust slot; both functions should list their kernel driver
```

`nvidia-persistenced` keeps device nodes open; the scripts stop it before unbinding and start it after.

## 4. NVIDIA Container Toolkit + CDI (optional)

Only needed if you run GPU containers on Linux. Install per NVIDIA's documentation, then generate a CDI
spec (`sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`). The spec describes device nodes
of the GPU *as currently bound*, so it must be regenerated after every return from VFIO;
`gpu-to-linux.sh` does it when `CDI_MODE` allows. See [gpu-handoff.md](gpu-handoff.md).

## 5. Docker

Install Docker Engine + Compose plugin from Docker's repository. The Windows container needs
`/dev/kvm`, `/dev/net/tun`, `/dev/vfio/vfio`, `/dev/vfio/<group>`, `NET_ADMIN`, `IPC_LOCK`, unlimited memlock.

## 6. Tools used by the scripts

`bash`, `sudo`, `flock` (util-linux), `fuser` (`psmisc`), `lspci` (`pciutils`), `timeout` (coreutils), `docker`,
optionally `shellcheck` for development.

## 7. Configure this project

**Simple case: nothing to configure for the GPU.**

```bash
scripts/status.sh               # read-only; shows what was auto-detected
scripts/gpu-to-vfio.sh --check  # guards only, changes nothing
```

Auto-detection (fail closed): exactly one NVIDIA display-class device, its audio function in the same
slot, the IOMMU group from sysfs (must contain only those two functions), the single `dockurr/windows`
container. If several candidates exist the scripts stop with an explicit error telling you which
value to set.

**The compose file.** Needed only to *create* the Windows container the first time (afterwards its path is
read from Docker's labels, and `start-windows.sh` uses `docker start`). Provide it with a two-line file:

```bash
printf 'WINDOWS_COMPOSE="/path/to/docker-compose.yml"
' > config/gpu.env
```

**Advanced case.** [config/gpu.env.example](../config/gpu.env.example) lists every override (explicit PCI
addresses, container name, driver names, timeouts, CDI). The file is sourced by root scripts: keep it
root-owned and not writable by others if you restrict who can run them.

## 8. Optional: launchers in your home directory

```bash
install/install-user-commands.sh --dry-run   # show what would be installed
install/install-user-commands.sh             # ~/start-windows.sh, ~/stop-windows.sh, ~/windows-status.sh
```

Each launcher is a one-line `exec` of the script in *this* clone (the path is detected at install time);
it contains no configuration or logic. The installer never overwrites a file that is not one of its own
launchers unless you pass `--force`, which first moves the old file to `<name>.bak-<timestamp>`.
