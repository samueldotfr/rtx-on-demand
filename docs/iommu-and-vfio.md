# IOMMU and VFIO

## IOMMU and groups

The IOMMU translates and restricts DMA from PCI devices. Linux places devices that cannot be
isolated from one another into the same **IOMMU group**. VFIO hands a *whole group* to a VM.

List groups:

```bash
for g in /sys/kernel/iommu_groups/*; do
  echo "group ${g##*/}:"; for d in "$g"/devices/*; do echo -n "  "; lspci -nns "${d##*/}"; done
done
```

### Why GPU and audio are handled together

A discrete GPU is a multi-function device: function 0 is the GPU, function 1 is the HDMI/DP audio
controller. They normally share one IOMMU group, so VFIO cannot give the GPU to a VM while Linux
keeps the audio function. Both must be bound to `vfio-pci`, and both must come back to Linux together.
The scripts also refuse a group containing anything else (`ALLOW_SHARED_GROUP=1` overrides this; do
not unless you know what else is in the group, e.g. a PCIe bridge is fine, a NIC is not).

## vfio-pci and /dev/vfio

`vfio-pci` is a stub driver that exposes a device to userspace (QEMU). When the group's devices are
bound to it, the kernel creates `/dev/vfio/<group>`. QEMU opens that node (plus `/dev/vfio/vfio`) and
keeps it open while the VM runs. Consequences:

- **QEMU must start after the bind**: with no `/dev/vfio/<group>` there is nothing to map into the container.
- **Windows must stop before the GPU returns to Linux**: while QEMU holds the group, the device
  cannot be safely unbound.

## driver_override (dynamic binding)

Every PCI device has `/sys/bus/pci/devices/<addr>/driver_override`. If set to `vfio-pci`, only that
driver may bind on the next probe. The recipe the scripts use:

1. write `vfio-pci` to `driver_override`
2. write the address to the current driver's `unbind`
3. write the address to `/sys/bus/pci/drivers_probe` → `vfio-pci` binds

Reverse: unbind, clear `driver_override` (write a bare newline: `echo > driver_override`; `: > driver_override` does **not** work, it sends no write to sysfs), verify it reads back `(null)`, then `drivers_probe` → `nvidia` / `snd_hda_intel` bind.

### Why not `vfio-pci.ids=` at boot?

That option claims every matching device at boot, so Linux never sees the GPU until you undo it.
That is a valid approach (simpler, and more robust for a GPU that is *only* for the VM), but it
defeats the purpose of this project: the GPU should be usable by Linux compute until Windows is wanted.
Dynamic binding is **one** approach, not the only one. Trade-off: more moving parts (the guards below),
and the state is runtime-only so a reboot returns to Linux.

## Guards before unbind (Linux → VFIO)

All must pass or the script stops:

1. Device IDs match (if configured) and the IOMMU group holds only the two functions.
2. Both functions currently use the Linux drivers.
3. No QEMU process references the GPU; `/dev/vfio/<group>` not already held.
4. `nvidia-smi` lists no compute processes.
5. No process other than `nvidia-persistenced` holds `/dev/nvidia*` or the GPU's `/dev/dri` nodes.
   Only nodes of *this* GPU are checked, so a different GPU used for the desktop does not block you.

Then: stop `nvidia-persistenced` (it holds device nodes open), `modprobe vfio-pci`, bind.

## Postconditions

After → VFIO: both functions on `vfio-pci`, `/dev/vfio/<group>` exists.
After → Linux: both functions on their Linux drivers, `driver_override` empty, `nvidia-persistenced`
active (if configured), `nvidia-smi -L` works, CDI regenerated if in use.

## Failure policy

A failed unbind or probe may leave the GPU in a half-moved state. The scripts print the state and
exit; they do not try to "undo". Inspect with `scripts/status.sh` and see [troubleshooting.md](troubleshooting.md).
A reboot always returns to Linux since nothing is persistent.
