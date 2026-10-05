# Gamepad

## Status

**Xbox controller: validated on our reference build.** It earlier did not work; it works now (older notes saying otherwise are obsolete).

Test performed:

1. Xbox controller connected to the Windows laptop running Moonlight; visible locally in `joy.cpl`.
2. Moonlight connected to the workstation.
3. **ViGEmBus 1.22.0** installed in the remote Windows.
4. A virtual Xbox controller appeared in `joy.cpl` **on the remote Windows**; it worked immediately.

Other controllers (DualShock/DualSense, Switch Pro, 8BitDo, etc.): **untested**.

## Chain

```
Xbox controller
      |
Moonlight client
      |
network
      |
Sunshine
      |
ViGEmBus
      |
virtual Xbox controller
      |
Windows game
```

## ViGEmBus is end-of-life

[ViGEmBus](https://github.com/nefarius/ViGEmBus) is archived / end-of-life. It worked for us, but you should know it is no longer maintained. As of our check of the Sunshine documentation
(October 2026), Sunshine states ViGEmBus remains available as a limited alternative for Xbox 360 and DualShock 4 gamepads, and that
**Virtual HID Driver** (LizardByte) is the actively developed replacement, supporting more controller types (Xbox One/Series, DualSense, Switch Pro, generic).
Sunshine's settings let you choose all available drivers, only Virtual HID Driver, or only ViGEmBus.

We have **not tested Virtual HID Driver**. Recommendation for new installs: read the current Sunshine docs and try the maintained driver first; fall back to ViGEmBus if needed. TODO: validate and document.

## Verify

- `joy.cpl` on the remote Windows shows a controller while one is connected on the client.
- If absent: no gamepad driver installed, controller not seen by the client, or Sunshine's gamepad option disabled. See [troubleshooting.md](troubleshooting.md).

## Keyboard and mouse

Work without extra drivers on our build.
