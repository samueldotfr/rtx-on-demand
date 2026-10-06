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
4. Stats overlay: Ctrl+Alt+Shift+S (see [shortcuts](#useful-moonlight-shortcuts)). Read host processing, network, **decode time** and **frame queue delay**.
5. Enable "Optimize game settings" only if you want Sunshine to change the host mode (it interacts with the VDD; effects untested).

## Useful Moonlight shortcuts

Both shortcuts are documented in the upstream [Moonlight Setup Guide](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide)
and are handled by the **client**, not by this project, Sunshine or Windows. Availability and exact behavior can differ
by client platform and version (for example the stats overlay is documented as not supported on Steam Link or
Raspberry Pi). Check your client's own documentation if a shortcut does nothing.

| Shortcut | Action (upstream description) |
|---|---|
| Ctrl + Alt + Shift + S | Toggle the performance stats overlay |
| Ctrl + Alt + Shift + M | Toggle mouse mode (pointer capture or direct control) |

### Ctrl + Alt + Shift + M: mouse capture / mouse mode

Some games use the mouse as a relative input to turn the camera and need the pointer to stay captured. If the
streamed pointer behaves like a desktop cursor that reaches the edge of the screen, the camera can stop turning in that
direction. On our setup we hit this in Returnal, and toggling mouse mode with Ctrl+Alt+Shift+M restored the expected
behavior. This is a Moonlight troubleshooting step for games that expect captured/relative mouse input, not a claim
about a bug specific to one game: other games may behave differently, and we did not investigate the root cause.

If it persists, check that the Moonlight window has focus, and that the client option documented upstream as
"Optimize mouse for remote desktop instead of games" (where your client has it) is not enabled for game streaming:
it targets desktop use, not games.

### Ctrl + Alt + Shift + S: performance stats overlay

While tuning an RTX on Demand setup, turn the overlay on to confirm the stream behaves as intended, then hide it
again once you are done, so it does not cover the game. Depending on client and version it can show:

- stream frame rate (received vs. rendered)
- decoding and rendering performance
- network latency and dropped frames
- video codec and resolution, when the client exposes them

Field names and the set of fields vary between clients and versions; do not expect all of them everywhere.

On our reference build it helped validate high-resolution, high-frame-rate streaming and tell apart four kinds of
problems: the host (encode/processing time), the network (latency, dropped frames), client decoding (decode time) and
client rendering (frame queue / render time). See [performance.md](performance.md).

## Living-room setup

Moonlight on a TV box + Xbox controller → Sunshine ([gamepad.md](gamepad.md)). Wired Ethernet recommended.
Our reference test used a laptop client, not a TV box.

## Network

Same LAN, no NAT in between. Internet streaming (VPN/port-forward) is out of scope and untested; never expose Sunshine/RDP directly.
