# Virtual display (headless Windows)

## Why a headless Windows needs a virtual monitor

With nothing plugged into the GPU, Windows may expose no active display. Sunshine captures a *display*
(DXGI desktop duplication), so no display means no stream, or a fallback mode at a poor resolution.
A **Virtual Display Driver (VDD)** adds an indirect-display monitor that Windows treats as real and that can
offer any mode you declare. An HDMI dummy plug is the hardware alternative (untested here).

Tested: [Virtual Display Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver) (VirtualDrivers / MikeTheTech). Follow
its README for installation; this project does not redistribute it.

## Terms: keep these separate

| Term | Meaning |
|---|---|
| **Declared mode** | A resolution/refresh listed in the VDD's settings file. Only an *offer* |
| **Active mode** | What Windows currently uses on that monitor (Settings → Display → Advanced display) |
| **Moonlight requested resolution** | What the client asks for in its settings |
| **Sunshine captured resolution** | What Sunshine actually grabs; follows the active display mode (and may be adjusted by Sunshine's own display-device settings) |
| **Windows refresh rate** | Refresh of the virtual monitor mode |
| **Stream FPS** | Frames actually captured/encoded/sent; limited by content, by Windows refresh and by target fps |
| **Client display refresh** | Physical panel of the client, independent of the stream |

Two consequences:
- **A mode in the XML is not enough.** If it is not *active* in Windows, Sunshine captures something else.
  Select it in Windows display settings (or via Sunshine's display-device configuration, untested here)
  and verify.
- A 120 fps stream needs: active 120 Hz mode **and** Moonlight set to 120 fps **and** content that actually changes 120 times a second.

## Our reference mode

**5120x1440 @ 120 Hz**, a single virtual monitor, declared in the VDD settings
(see [examples/vdd_settings.xml.example](../examples/vdd_settings.xml.example)), made active in Windows, and streamed with AV1. Other
resolutions were available in the list; they were not all validated one by one.

The XML schema and file location depend on the VDD version. Compare the example against the file shipped
with your installed version.

## The VirtIO display problem

Dockur's QEMU also exposes an emulated display adapter (VirtIO/virtio-vga class) used by the
noVNC console. When the VDD becomes the primary display, Windows detaches the VirtIO display.
Observed: **noVNC may turn black.** This is not necessarily a failure: the VM is alive and Sunshine still works.
To regain console access, use RDP/SSH/Sunshine, or temporarily disable the VDD. (We did not test how to
re-attach VirtIO as secondary while keeping VDD primary.)

## Verify

1. Device Manager → Display adapters: the NVIDIA GPU and the virtual display adapter both present.
2. Settings → Display → Advanced display: monitor shows the expected resolution and refresh.
3. Sunshine log at stream start: captured resolution and output.
4. Moonlight stats overlay (Ctrl+Alt+Shift+S): resolution and fps.

No identifiers (monitor IDs, serials) belong in public issues.
