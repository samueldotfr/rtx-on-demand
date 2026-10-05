# Moonlight clients

[Moonlight](https://moonlight-stream.org) is the client. This project makes no changes to it.

| Client | Status |
|---|---|
| Windows laptop | **Validated.** 5120x1440 AV1 at ~120 fps, low decode time, controller works |
| Ubuntu desktop | **Known issue** on our machine: abnormal frame queue delay in fullscreen. Unresolved, cause unknown. See [known-issues.md](known-issues.md) |
| TV / mini-PC / Android TV / Apple TV / handheld | **Untested** here |

## Settings to check first

1. Resolution and fps match your active virtual-display mode ([virtual-display.md](virtual-display.md)).
2. Codec: Automatic can pick something your client decodes slowly; set explicitly while testing (see [sunshine.md](sunshine.md)).
3. Bitrate: scale with resolution and LAN quality. We did not derive a formula.
4. Stats overlay: Ctrl+Alt+Shift+S. Read host processing, network, **decode time** and **frame queue delay**.
5. Enable "Optimize game settings" only if you want Sunshine to change the host mode (it interacts with the VDD; effects untested).

## Living-room setup

Moonlight on a TV box + Xbox controller → Sunshine ([gamepad.md](gamepad.md)). Wired Ethernet recommended.
Our reference test used a laptop client, not a TV box.

## Network

Same LAN, no NAT in between. Internet streaming (VPN/port-forward) is out of scope and untested; never expose Sunshine/RDP directly.
