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

## Testing limits

**Hardware state transitions cannot be validated by mocks alone.** The first real VFIO→Linux run of these scripts
failed although `bash -n`, ShellCheck, the mock tests, dry-runs and an idempotent start were all green: the mocks
used regular files for sysfs, and `: > attr` empties a regular file but sends no `write()` to a real sysfs attribute,
so `driver_override` was never cleared. Mock tests here therefore model the *semantics* that matter (see the FIFO test in
`tests/test-mocks.sh`), and every change to a transition must also be checked on real hardware by a human, from a
known state, with a documented recovery command.

## Reporting a hardware result

Open an issue with: CPU/chipset, GPU, kernel, driver version, IOMMU group layout, what worked, what
did not, and logs with private data removed.
