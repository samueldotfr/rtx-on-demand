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
- Run `tests/test-mocks.sh` and `tests/test-installer.sh` (hardware-free; temp dirs only).
- Scans of `/proc` must ignore a PID that exits mid-scan but must not silently drop a process that exists and cannot be read.
- Do not hard-code PCI addresses, IOMMU groups, paths or names; they are auto-discovered (fail closed when ambiguous) or come from the optional `config/gpu.env` overrides.
- Scripts that modify anything must call `refuse_if_mocked` and `ensure_root "$@"`; `--dry-run`/`--check` must have no side effects. Test discovery logic with `HGW_FAKE_SYSFS` (a fake sysfs tree) and a fake `docker` in `PATH`, never on live hardware.

## Reporting a hardware result

Open an issue with: CPU/chipset, GPU, kernel, driver version, IOMMU group layout, what worked, what
did not, and logs with private data removed.
