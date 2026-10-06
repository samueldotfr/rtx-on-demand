# Troubleshooting

Each entry: **Symptom**, **Cause / possible causes** (only established causes stated as causes), **How to verify**, **Fix**, **Do not confuse with**.
Always start with `scripts/status.sh` (read-only). Commands marked `sudo` change nothing unless stated.

## GPU refuses to leave NVIDIA (unbind hangs or is refused)

- **Symptom:** `gpu-to-vfio.sh` fails at the guards or at unbind; unbind blocks until timeout.
- **Cause / possible causes:** A process still has a GPU device node open, or `nvidia-persistenced` is running. Other causes possible.
- **How to verify:** `sudo fuser -v /dev/nvidia* /dev/dri/*`; `nvidia-smi --query-compute-apps=pid,process_name --format=csv`; `systemctl status nvidia-persistenced`.
- **Fix:** Stop the listed workloads/containers; the script stops `nvidia-persistenced` itself. Retry `--check`. If unbind hangs, reboot is the only certain recovery.
- **Do not confuse with:** A GPU used for the host desktop (not supported).

## nvidia-persistenced holds the GPU

- **Symptom:** Unbind fails although no compute process is listed.
- **Cause / possible causes:** The persistence daemon keeps `/dev/nvidia*` open by design.
- **How to verify:** `sudo fuser -v /dev/nvidia*` shows `nvidia-persiste`.
- **Fix:** Let the script stop it (`PERSISTENCED_UNIT` in config). Set it empty only if you do not run the service.
- **Do not confuse with:** A real workload: the guard ignores only persistenced.

## Processes holding /dev/nvidia*

- **Symptom:** Guard message `processes hold GPU device nodes (pid:name)`.
- **Cause / possible causes:** Containers, monitoring exporters, Xorg/Wayland on the GPU, CUDA apps.
- **How to verify:** `sudo fuser -v /dev/nvidia*`, `docker ps`.
- **Fix:** Stop or restart those processes without GPU access; for containers `docker stop`.
- **Do not confuse with:** Processes on a different GPU: only nodes of the configured GPU are checked.

## VFIO group missing

- **Symptom:** `/dev/vfio/<group>` does not exist after the bind, or compose fails: *no such device*.
- **Cause / possible causes:** Functions not on `vfio-pci`, the IOMMU is off, or the wrong group number is in `.env`.
- **How to verify:** `scripts/status.sh`; `ls /dev/vfio`; `dmesg | grep -i -E 'vfio|iommu'`.
- **Fix:** Enable the IOMMU ([host-setup.md](host-setup.md)), re-run `gpu-to-vfio.sh`, fix `VFIO_GROUP` in `.env` to what `status.sh` prints.
- **Do not confuse with:** Group present but held by QEMU (that is state C).

## Wrong driver_override

- **Symptom:** A function binds to the wrong driver after a transition, or the status says INCONSISTENT with override set.
- **Cause / possible causes:** A previous attempt was interrupted after writing `driver_override`.
- **How to verify:** `cat /sys/bus/pci/devices/<addr>/driver_override`.
- **Fix:** With Windows stopped: `sudo scripts/gpu-to-linux.sh` (clears it). Manual: unbind, `echo > /sys/bus/pci/devices/<addr>/driver_override` (a bare newline; `: >` sends no write and does nothing), check it reads `(null)`, then `echo <addr> > /sys/bus/pci/drivers_probe`.
- **Do not confuse with:** `(null)` is the normal empty value.

## QEMU still holds /dev/vfio

- **Symptom:** `gpu-to-linux.sh` refuses: `/dev/vfio/<group> still held`.
- **Cause / possible causes:** Windows shutdown did not finish, or a stale QEMU process remains.
- **How to verify:** `sudo fuser -v /dev/vfio/*`; `pgrep -a qemu-system`; `docker ps`.
- **Fix:** Wait for shutdown (Windows may install updates on stop); raise `STOP_TIMEOUT`. As a last resort `docker kill` (risks disk consistency in the guest).
- **Do not confuse with:** A different VM using another group.

## NVIDIA does not come back

- **Symptom:** After `gpu-to-linux.sh`, `nvidia-smi` fails or drivers not bound.
- **Cause / possible causes:** Kernel module not loaded, probe failed, or the GPU did not reset cleanly. We did not see this on the reference build; cause would need investigation.
- **How to verify:** `dmesg | tail -50`, `lsmod | grep nvidia`, `lspci -nnk -s <slot>`.
- **Fix:** `sudo modprobe nvidia`, re-probe; if still failing, reboot.
- **Do not confuse with:** A held `/dev/nvidia*` after return (different symptom).

## Stale CDI spec

- **Symptom:** GPU containers fail to start after a round trip (device/spec errors).
- **Cause / possible causes:** The CDI spec no longer matches the device state. Regeneration is the remedy used by this project.
- **How to verify:** `nvidia-ctk cdi list`; compare with `/etc/cdi/nvidia.yaml` timestamp.
- **Fix:** `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` or run `gpu-to-linux.sh` with `CDI_MODE=on`.
- **Do not confuse with:** Container Toolkit runtime misconfiguration.

## Windows does not see the RTX

- **Symptom:** No NVIDIA adapter in Device Manager, or Code 43.
- **Cause / possible causes:** Missing guest driver, QEMU arguments not applied, or a GPU/VM configuration problem. Code 43 causes vary.
- **How to verify:** `docker inspect` the container's args; `pgrep -a qemu-system` shows two `vfio-pci` devices; Device Manager.
- **Fix:** Install the NVIDIA driver in Windows; verify `ARGUMENTS`; verify `multifunction=on` on the GPU function.
- **Do not confuse with:** Remote console showing a basic display adapter only (VirtIO/VDD).

## Sunshine uses the wrong GPU or display

- **Symptom:** Black screen, wrong resolution, or software encoding.
- **Cause / possible causes:** `adapter_name`/`output_name` not set or pointing elsewhere.
- **How to verify:** Sunshine log lists adapters and outputs at startup.
- **Fix:** Set both in `sunshine.conf` ([sunshine.md](sunshine.md)), restart the Sunshine service.
- **Do not confuse with:** VDD mode not active (below).

## VDD wrong resolution

- **Symptom:** Moonlight stream resolution differs from the intended one.
- **Cause / possible causes:** The VDD mode is not selected, or Moonlight requested a different mode.
- **How to verify:** Windows Advanced display; Moonlight overlay.
- **Fix:** Select the mode in Windows; align Moonlight settings ([virtual-display.md](virtual-display.md)).
- **Do not confuse with:** Client scaling.

## Mode declared but not active

- **Symptom:** Mode is in the XML but not selectable or not in use.
- **Cause / possible causes:** The driver did not reload the settings, or the mode is invalid for that driver version. Not established which in each case.
- **How to verify:** Settings → Display → Advanced → resolution list.
- **Fix:** Reload/restart the driver per its README; compare the XML with the shipped example for your version.
- **Do not confuse with:** A mode that is active but not requested by the client.

## H.264 above 4096 px

- **Symptom:** Encoder errors or hangs at 5120x1440 with H.264.
- **Cause / possible causes:** Observed on our reference setup: NVENC width limit for H.264. We did not test other GPU generations.
- **How to verify:** Sunshine log at stream start.
- **Fix:** Use AV1/HEVC or reduce width to ≤4096.
- **Do not confuse with:** Client decode problems.

## HEVC slow on client

- **Symptom:** Large decode time in the overlay with HEVC.
- **Cause / possible causes:** Observed on one Intel client; cause not investigated.
- **How to verify:** Overlay decode ms, compare codecs.
- **Fix:** Try AV1 or H.264 at a lower resolution; update client drivers.
- **Do not confuse with:** Network latency.

## Static desktop ~30 FPS

- **Symptom:** Overlay shows 30-45 fps on an idle desktop.
- **Cause / possible causes:** Desktop duplication only delivers frames when content changes.
- **How to verify:** Run TestUFO or a game.
- **Fix:** None needed. See [performance.md](performance.md).
- **Do not confuse with:** A real 30 fps cap (check Moonlight fps setting and active refresh).

## Audio absent

- **Symptom:** Video fine, no sound.
- **Cause / possible causes:** No capturable Windows playback endpoint.
- **How to verify:** Windows Sound → Output lists *Speakers*; QEMU args contain `ich9-intel-hda`/`hda-output`.
- **Fix:** Add the HDA arguments ([audio.md](audio.md)); restart the VM; set the endpoint as default; restart Sunshine.
- **Do not confuse with:** Client volume or muted Moonlight.

## Gamepad absent

- **Symptom:** Controller works locally but not in the remote Windows.
- **Cause / possible causes:** No virtual-gamepad driver in the guest (this was our case before ViGEmBus).
- **How to verify:** `joy.cpl` in the remote Windows.
- **Fix:** Install a driver Sunshine supports ([gamepad.md](gamepad.md): ViGEmBus is EOL; Virtual HID Driver is the maintained one, untested here).
- **Do not confuse with:** Controller not recognized by the client itself.

## Sunshine pairing fails

- **Symptom:** PIN rejected or host not found.
- **Cause / possible causes:** Wrong ports, firewall, different network, stale pairing. Not always determinable.
- **How to verify:** Moonlight reaches `https://<ip>:47990`; Sunshine log.
- **Fix:** Re-enter the PIN promptly in the web UI; remove the stale device and re-pair; check LAN bind IP.
- **Do not confuse with:** Web UI login problems.

## Sunshine UI CSRF / form rejected

- **Symptom:** Form submissions are refused in the web UI.
- **Cause / possible causes:** Cross-site protection when the page origin differs from the one used to load it (our hypothesis, not confirmed).
- **How to verify:** Browser console / UI error text.
- **Fix:** Open the UI via the same address you use to submit; retry in a fresh tab.
- **Do not confuse with:** Wrong credentials.

## noVNC black after VirtIO detach

- **Symptom:** Port 8006 console is black.
- **Cause / possible causes:** The VirtIO display is detached when the VDD is primary; see [virtual-display.md](virtual-display.md).
- **How to verify:** Stream still works; the VM is up.
- **Fix:** Use Moonlight/RDP/SSH. Not necessarily a fault.
- **Do not confuse with:** A hung VM (check `docker logs`).

## SSH host key changed after Windows reinstall

- **Symptom:** SSH warns `REMOTE HOST IDENTIFICATION HAS CHANGED`.
- **Cause / possible causes:** A new Windows install generates a new host key.
- **How to verify:** The warning itself.
- **Fix:** Verify you reinstalled, then `ssh-keygen -R <host>` and reconnect.
- **Do not confuse with:** A real man-in-the-middle: confirm first.

## Reboot / crash caveats

- **Symptom:** Host rebooted while Windows ran, or the host crashed.
- **Cause / possible causes:** Transitions are runtime-only; the matrix of crash points is not fully tested.
- **How to verify:** `scripts/status.sh` after boot.
- **Fix:** Expect state A after a reboot. Check Windows disk integrity on next boot; do not start Windows until `status.sh` reports LINUX or VFIO_PARKED.
- **Do not confuse with:** A graceful shutdown with `stop-windows.sh`.
