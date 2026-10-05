# Windows 11 IoT Enterprise LTSC 2024

## Why consider it for a headless workstation

- **Long-term servicing:** no feature updates for the life of the release, so fewer surprise changes to a VM you rarely touch.
- **Relatively lean:** fewer bundled consumer apps than retail editions.
- **Fits a dedicated gaming/workstation VM** that exists to run a handful of apps.

These are properties of the LTSC channel in general; we did not benchmark LTSC against other editions.

## Licensing: read this

- **Our reference build runs an *Evaluation* edition.** That is for testing, it is time-limited,
  and **it is not a recommendation for permanent use.**
- For permanent use you need an appropriate license for the edition you run. IoT Enterprise LTSC has
  specific licensing channels (OEM/embedded); check Microsoft's terms for your situation.
- This repository provides **no keys, no ISOs and no activation workarounds**, and does not
  recommend grey-market keys. Do not open issues or PRs asking for them.

## Language and keyboard

The Evaluation ISO we used is **English only** (en-US). A French keyboard layout can be added separately inside Windows
(Settings → Time & language → Language & region → add keyboard) or via dockur's `KEYBOARD` variable. We did not
test every combination of the two.

## dockur

`VERSION: "11i"` selects the IoT Enterprise LTSC 2024 Evaluation download in dockur (name at time of writing; verify
in dockur's README). Dockur-specific.

## Other editions

Regular Windows 10/11 also work with dockur in principle. They are **untested** in this project.
