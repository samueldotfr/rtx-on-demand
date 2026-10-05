# Security

This setup gives a network-reachable Windows VM direct hardware access. Treat it accordingly.

## Network exposure

- Publish Sunshine, RDP, SSH and noVNC **only on a LAN address** (the example compose does; never `0.0.0.0` on an internet-facing host).
- **Never forward these ports from your router.** Remote access, if you need it, goes through a VPN you trust (not covered or tested here).
- Disable what you do not use: RDP, SSH, the noVNC port.

## Credentials

- The compose file requires the Windows password from `.env`; choose a strong one and do not reuse it.
- Sunshine's web UI has its own admin account: set a strong password; keep `origin_web_ui_allowed = lan`.
- Sunshine's config directory holds credentials and paired-client data: never share or commit it.
- SSH into Windows: use keys, disable password authentication once it works.
- `config/gpu.env` is sourced by root scripts: root-owned, mode 600.

## VFIO trust boundary

The guest controls a PCI device that can perform DMA. The IOMMU restricts it to the guest's memory, but
GPU firmware/driver bugs, reset bugs and a shared IOMMU group weaken that. Do not pass through a group that contains
other devices (the scripts refuse). Do not run untrusted software in the VM and assume the host is safe from a
compromised guest: the host's Docker socket, storage and LAN are one exploit away.

## Host script privileges

`start-windows.sh`/`stop-windows.sh` need root (sysfs writes, docker). If you wrap them in sudo rules or a
web trigger, restrict the exact command; do not allow arbitrary arguments or config paths.

## Repository hygiene

Before publishing anything derived from your setup: remove hostnames, usernames, addresses, MACs, serials, GPU UUIDs, keys, state files and screenshots with such data.
See [CONTRIBUTING.md](../CONTRIBUTING.md).
