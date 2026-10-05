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

`bash`, `flock` (util-linux), `fuser` (`psmisc`), `lspci` (`pciutils`), `timeout` (coreutils), `docker`,
optionally `shellcheck` for development.

## 7. Configure this project

```bash
cp config/gpu.env.example config/gpu.env
$EDITOR config/gpu.env          # PCI addresses, container name, compose dir
sudo chown root:root config/gpu.env && sudo chmod 600 config/gpu.env   # it is sourced by root scripts
scripts/status.sh               # read-only sanity check
scripts/gpu-to-vfio.sh --check  # guards only
```

Find your PCI addresses with `lspci -nn | grep -i nvidia`.
