# Contributing

Thanks for helping. This is an advanced homelab project; the most valuable contributions are
**honest reports from other hardware** and fixes to unclear docs.

## Ground rules

1. **Say what you tested.** Use the labels `Observed on our reference setup`, `untested`,
   `known limitation`, `TODO`. Do not turn one machine's result into a general rule.
2. **No private data.** No real hostnames, usernames, LAN/WAN addresses, MAC addresses, serials,
   GPU UUIDs, license keys, tokens, Sunshine state, or screenshots containing them.
3. **No piracy.** No Windows keys, activation bypasses, ISOs or links to grey-market keys.
4. **Do not commit binaries** (drivers, installers, images). Link to the upstream project.
5. **Scripts must fail closed.** An unknown state means stop and report, never "try to fix it".

## Script changes

- Bash, `set -Eeuo pipefail`, quoted expansions, no `eval`, timeouts on anything that can block.
- Every transition needs guards before and postconditions after.
- Run `bash -n scripts/*.sh scripts/lib/*.sh` and `shellcheck scripts/*.sh scripts/lib/*.sh`.
- `scripts/status.sh` must stay strictly read-only.
- Do not hard-code PCI addresses, IOMMU groups, paths or names; they come from `config/gpu.env`.

## Reporting a hardware result

Open an issue with: CPU/chipset, GPU, kernel, driver version, IOMMU group layout, what worked, what
did not, and logs with private data removed.
