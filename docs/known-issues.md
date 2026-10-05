# Known issues and limitations

## Open issues

### Ubuntu Moonlight client: high frame queue delay in fullscreen

- **Windows client:** excellent behavior observed (see [performance.md](performance.md)).
- **One particular Ubuntu client machine:** abnormal frame queue delay in fullscreen.
- **Server:** identical in both cases.
- **Cause: unknown.** Not resolved. Do not read any explanation into this; it is a *client-side* observation on one machine.
- **Future investigation:** compare windowed vs fullscreen, decoder path, compositor, other Ubuntu clients.

### H.264 above 4096 px width
Observed failures/hangs at 5120x1440 with H.264 on NVENC. Use AV1 or HEVC (client permitting) or lower the resolution.

### HEVC decode latency on one client
Very slow decoding on our Intel client; may not apply to yours.

### noVNC black after VDD
When the Virtual Display Driver is the primary display the VirtIO display is detached and the noVNC console can go black. Not necessarily a fault.

### Reboot/crash matrix incomplete
Behavior of host reboot, host crash, or Docker daemon restart in state B (parked) or C (Windows running) is only partly tested. Transitions are
non-persistent, so a host reboot returns the GPU to Linux, but the Windows disk's consistency after a hard crash is as for any VM.

### Gamepad driver is end-of-life
ViGEmBus works but is archived; Virtual HID Driver is the maintained alternative and is untested here ([gamepad.md](gamepad.md)).

## Untested (do not assume it works)

| Area | Status |
|---|---|
| Intel CPU host | untested (AMD tested) |
| AMD / Intel GPU | untested (NVIDIA tested) |
| Distros other than Ubuntu 24.04 | untested |
| VM runtime other than dockur/windows | untested |
| Gamepads other than Xbox | untested |
| TV / Android / Apple Moonlight clients | untested |
| Single-GPU host (GPU also drives host display) | untested, unsupported by guards |
| Multiple NVIDIA GPUs | untested; scripts handle one configured GPU |
| Anti-cheat games in a VM | untested |
| HDR, 10-bit | untested |
| Remote access outside the LAN | untested |

## Evaluation edition
Our Windows is an Evaluation edition: time-limited, for testing. See [windows-ltsc.md](windows-ltsc.md).
