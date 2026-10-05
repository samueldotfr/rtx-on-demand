# Hardware requirements

Everything here is either a hard technical requirement or marked with how it was tested.

## Required

| Item | Why | Notes |
|---|---|---|
| CPU + chipset with IOMMU (AMD-Vi / Intel VT-d) | VFIO needs DMA remapping | Enable in BIOS. **Reference: AMD-Vi. Intel hosts: untested.** |
| Virtualization (SVM / VT-x) and KVM | QEMU/KVM | `/dev/kvm` must exist |
| A GPU you can dedicate | Passed to the VM as a whole PCI device | **Reference: NVIDIA. AMD GPUs: untested** (AMD has its own reset and NVENC-equivalent differences) |
| GPU and audio function in a clean IOMMU group | The group is the unit of isolation | Scripts refuse a group containing other devices. See [iommu-and-vfio.md](iommu-and-vfio.md) |
| Host RAM ≥ guest RAM + host needs | VFIO pins all guest RAM | Reference: 32 GB host, 16 GB guest |
| Disk space | Windows disk is a sparse file | Reference: 512 GB virtual size |
| Docker + Compose | dockur/windows | |
| Network | Streaming | Wired LAN strongly preferred. Reference measurement: ~1 ms LAN |

## GPU used for the host display

The scripts assume the passthrough GPU is **not** driving the host's own console/desktop. A
separate iGPU (as on the reference mini-PC) or a headless server avoids this problem. Single-GPU
hosts that need the GPU for their own display: **untested** and not supported by these guards.

## Server-side encoding

NVENC generation matters for codecs and maximum resolution. On our reference GPU, H.264 failed at
a width above 4096 px; AV1 encoding worked (the card has AV1 NVENC). Check your card's NVENC
capabilities (NVIDIA's Video Encode and Decode support matrix).

## Clients

Any Moonlight client. Hardware decode capability decides which codec/resolution is usable
(see [moonlight.md](moonlight.md)). Validated: Windows laptop client. See [known-issues.md](known-issues.md)
for an Ubuntu client problem.

## Reference machine

See [reference-build.md](reference-build.md).
