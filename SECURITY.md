# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for a security problem. Use GitHub's private vulnerability
reporting ("Report a vulnerability" in the Security tab of
[samueldotfr/rtx-on-demand](https://github.com/samueldotfr/rtx-on-demand)). Include the affected
script or document and steps to reproduce.

## Scope and threat model

This project is documentation plus root-level shell scripts that rebind a PCI device. The most
relevant risks:

- **The scripts run as root** and write to `/sys/bus/pci`. They read a config file that is
  *sourced by bash*: only root should be able to write the optional `config/gpu.env`.
- **A Windows VM with a passed-through GPU is a large trust boundary.** A VFIO guest has DMA
  access to its device. The IOMMU confines it, but the guest is not sandboxed like an ordinary
  container. See [docs/security.md](docs/security.md).
- **Exposed services**: Sunshine web UI, RDP, noVNC and SSH must not be reachable from the internet.
- **Credentials**: never commit `.env`, Sunshine state, SSH keys or Windows keys. The `.gitignore`
  is strict, but it is not a substitute for reviewing `git diff` before every commit.

No security guarantees are given; see the LICENSE.
