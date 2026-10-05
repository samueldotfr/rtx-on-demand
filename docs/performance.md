# Performance

All numbers are **Reference build results**: one server, one network, one client, one day. They are not
benchmarks, not guarantees, and not reproducible on arbitrary hardware.

## Where time goes

| Stage | Component | What to look at |
|---|---|---|
| **Server** | Capture (DXGI) | Capture rate is bounded by how often the display content changes and by the active refresh rate |
| | Encode (NVENC) | Codec, resolution, bitrate; Sunshine log shows encoder problems |
| | GPU | Game load competes with NVENC for the same GPU |
| **Network** | LAN | Latency and packet loss; Moonlight overlay shows both |
| **Client** | Decode | Hardware decoder and codec; overlay "average decoding time" |
| | Frame queue | Overlay "frame queue delay": frames waiting to be shown. Should be near zero |
| | Render/present | Client GPU, compositor, fullscreen mode, display refresh |

## Reference results

AV1, 5120x1440, target 120 fps, Windows client, LAN:

- ~119.94 fps observed in one valid test
- client decode ~0.46 ms
- network ~1 ms in that measurement
- frame queue very low on the Windows client

No Man's Sky: native 5120x1440, high/Ultra settings according to our test, ~85-90 FPS observed.

Codec lessons at 5120x1440 (Observed on our reference setup, not a universal rule): H.264 failed above 4096 px width; HEVC worked
server-side but decoded very slowly on our particular Intel client; AV1 gave the best result. See [sunshine.md](sunshine.md).

## Why a static desktop shows ~30-45 FPS

Desktop duplication only produces a new frame when the screen changes. An idle desktop can legitimately report 30-45 fps (or less) in the overlay.
**That does not mean the pipeline is limited to 30 fps.** To test the real ceiling, show continuously animated content: a browser
motion test such as TestUFO, or a game. Only then does "120 fps" mean something.

## Test procedure we suggest

1. Confirm the *active* Windows mode is the intended resolution/refresh ([virtual-display.md](virtual-display.md)).
2. Set Moonlight to the same resolution and fps, codec explicit.
3. Run animated content; open the stats overlay.
4. Record: fps, decode ms, network ms, frame queue delay, dropped frames. Change one variable at a time.
5. Compare Windows vs other clients before blaming the server.

## Not measured

Power consumption, end-to-end input latency, 10-bit/HDR, multi-client, bitrate sweeps, other GPUs/hosts.
