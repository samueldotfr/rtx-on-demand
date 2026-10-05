# Sunshine (streaming host, inside Windows)

[Sunshine](https://github.com/LizardByte/Sunshine) captures the desktop/game, encodes it, and serves
Moonlight clients. Install it in the Windows guest from the upstream releases; nothing is redistributed here.
Option names change between versions: treat [examples/sunshine.conf.example](../examples/sunshine.conf.example) as illustrative.

## Installation and service

Use the upstream Windows installer, let it install the Sunshine service so it starts at boot without a login
session on the console (important for a headless VM), then confirm it is running in `services.msc`. Auto-login
and what happens at a locked screen were only lightly tested on our build.

## Web UI and pairing

- Web UI: `https://<windows-ip>:47990` (HTTPS, self-signed certificate: the browser warning is expected).
  Create the admin account on first visit. Keep it LAN-only (`origin_web_ui_allowed = lan`).
- Pairing: in Moonlight add the host, it shows a PIN, enter the PIN in Sunshine's **PIN** page.
- Forms in the UI are protected against cross-site requests; if a form POST is rejected, load the UI via
  the same hostname/IP you use for the browser session and retry (see [troubleshooting.md](troubleshooting.md)).
- Sunshine stores credentials, paired-device records and a device identity in its config directory.
  **Never copy or publish that directory.**

## Default ports

With the default base port 47989: TCP 47984, 47989, 47990 (UI), 48010; UDP 47998-48000, 48002, 48010. The example
compose publishes them on the LAN IP only. Verify against Sunshine's docs for your version.

## Capture and encode

- **Capture:** DXGI desktop duplication of the (virtual) display.
- **Encoder:** NVENC on the passed-through GPU (`encoder = nvenc`).
- **adapter_name / output_name:** select the GPU and display. With a VDD and a VFIO GPU, ensure Sunshine uses the NVIDIA adapter and the
  virtual monitor. The Sunshine log lists the available adapters/outputs at startup. A wrong output is a classic cause of black or
  wrong-resolution streams ([troubleshooting.md](troubleshooting.md)).

## Codecs: what we saw at 5120x1440

Observed on our reference setup (not a rule):

| Codec | Result |
|---|---|
| H.264 | **Failed**: NVENC limits H.264 to ≤4096 px width in our experience; above that we saw errors/hangs |
| HEVC | Server worked. **Very high decode latency on our particular Intel client** |
| AV1 | Best result: ~119.94 fps, ~0.46 ms decode on our Windows client |

Choose codec and resolution from **client** capability: its hardware decoder, its supported
max resolution per codec, and its drivers. Test with Moonlight's stats overlay. A different client may reverse
this ranking. See [performance.md](performance.md).

## Gamepad

See [gamepad.md](gamepad.md).
