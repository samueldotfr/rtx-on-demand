# Reference build

The machine this was developed and validated on. Nothing below is required.
The scripts auto-detect the GPU, audio function, IOMMU group and container; the only value that cannot be discovered is
the compose file path (read from the container labels once the container exists).

| Layer | Detail |
|---|---|
| Host | GMKtec NucBox K12, AMD Ryzen 7 H 255, ~32 GB DDR5 |
| OS | Ubuntu 24.04 |
| GPU | NVIDIA GeForce RTX 4070 Ti SUPER 16 GB, PCI functions `01:00.0` (GPU) and `01:00.1` (HDMI audio) |
| IOMMU | AMD-Vi, both functions in one IOMMU group (number 17 on this machine; yours will differ) |
| Linux GPU stack | NVIDIA open driver 595.x, NVIDIA Container Toolkit, CDI |
| Normal Linux bindings | `nvidia` / `snd_hda_intel` |
| VM runtime | dockurr/windows, QEMU/KVM, q35, UEFI |
| VM sizing | 12 vCPU, 16 GB RAM, 512 GB sparse disk |
| Guest | Windows 11 IoT Enterprise LTSC 2024 **Evaluation**, English ISO |
| Display | Virtual Display Driver, one virtual monitor, 5120x1440 @ 120 Hz |
| Streaming | Sunshine (DXGI + NVENC, AV1), Moonlight |
| Audio | `ich9-intel-hda` + `hda-output`, QEMU audio backend `none` |
| Input | keyboard, mouse OK; Xbox controller via ViGEmBus 1.22.0 |

## Results

See [performance.md](performance.md). Observed, not guaranteed.

## What was machine-specific and is parameterized

PCI addresses, IOMMU group, container name, compose directory, LAN bind address, VM sizing, SMT topology, virtual display mode,
GPU model name (detected, not hard-coded).

## Not covered by this repo

Our own surrounding automation. This repository intentionally contains only the generic GPU-sharing logic.
