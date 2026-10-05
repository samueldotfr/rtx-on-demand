# Audio on a headless VM

## Problem

With no physical HDMI display attached, the GPU's HDMI audio function may expose **no usable
playback endpoint** in Windows (the endpoint belongs to a connected monitor). Sunshine captures the
default Windows playback device; if none exists, there is nothing to capture and the stream is silent.

We describe what we observed; the exact reason an HDMI audio endpoint does not appear is a Windows/driver
behavior we did not investigate in depth.

## Solution used by the reference build

Give Windows a **virtual sound card** from QEMU:

```
-audiodev none,id=snd0
-device ich9-intel-hda,id=hda0,bus=pcie.0,addr=0x7
-device hda-output,bus=hda0.0,audiodev=snd0
```

- `ich9-intel-hda` is an emulated Intel HD Audio controller.
- `hda-output` is a codec on it (a playback "Speakers" jack).
- `audiodev none` is a QEMU audio backend that discards samples.

Windows binds its inbox *High Definition Audio Device* driver and creates a **Speakers** endpoint.
Sunshine captures that endpoint and sends it through Moonlight.

## The QEMU backend does not need to make sound

Nothing is played on the host: what we need is a **capturable Windows endpoint**, not
host playback. That is why the backend is `none`. Sound is heard on the Moonlight client.

## Notes

- The GPU's own HDMI audio function is still passed through (required by the IOMMU group,
  see [iommu-and-vfio.md](iommu-and-vfio.md)); it is just not the stream's source.
- The PCI address `0x7` on `pcie.0` worked on the reference build; if QEMU reports a conflict, choose another free slot.
- Verify in Windows: Sound settings → Output shows *Speakers (High Definition Audio Device)*; in Sunshine's log the audio sink is found.
- Microphone/audio-in from the client: untested.
