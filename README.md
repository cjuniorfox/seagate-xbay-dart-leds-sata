# Seagate xBay SATA LED Fix Packages

This repository builds Debian packages that restore SATA activity/presence LED behavior for Seagate xBay NAS devices based on Armada 370.

On vanilla kernel, the white SATA LEDs are not usable as expected on these boards. This project provides:

1. A patched `sata_mv` module enabling SoC SATA LED presence control.
2. A `leds-dart` LED driver module that switches each SATA LED pin between GPIO mode and SATA-controller mode.
3. A DTB with the `seagate,dart-leds` node and pinctrl states required by the driver.

## What Each Package Contains

1. `linux-modules-sata-mv-seagate-nas-xbay_<kernel-version>_armhf.deb`
: Installs `sata_mv.ko.xz` under `/lib/modules/<kernel-version>/kernel/drivers/ata/`.

2. `linux-modules-leds-dart-seagate-nas-xbay_<kernel-version>_armhf.deb`
: Installs `leds-dart.ko.xz` under `/lib/modules/<kernel-version>/kernel/drivers/leds/` and installs DTB at `/boot/dtb-<kernel-version>/marvell/armada-370-seagate-nas-4bay.dtb`.

Both packages run `depmod` and `update-initramfs` in `postinst/postrm`.

## Important Requirement

Install and use package versions that match the running kernel release.

Example:

1. Running kernel: `6.12.111-1+deb13-armmp`
2. Install packages built for `6.12.111-1`.

If versions do not match, modules will not load.

Check the running kernel:

```bash
uname -r
```

## Install Order

Even without explicit package dependency, `leds-dart` is intended to work with the patched `sata_mv` behavior.

Install in this order:

1. `linux-modules-sata-mv-seagate-nas-xbay_..._armhf.deb`
2. `linux-modules-leds-dart-seagate-nas-xbay_..._armhf.deb`

Example:

```bash
sudo dpkg -i linux-modules-sata-mv-seagate-nas-xbay_<version>_armhf.deb
sudo dpkg -i linux-modules-leds-dart-seagate-nas-xbay_<version>_armhf.deb
sudo reboot
```

## Compatible Devices

Target platform is Seagate DART/xBay family based on Armada 370, with SATA LED pins muxed as in the DART device tree.

Based on [linux/arch/arm/boot/dts/marvell/armada-370-seagate-nas-xbay.dtsi](linux/arch/arm/boot/dts/marvell/armada-370-seagate-nas-xbay.dtsi):

1. Seagate NAS 4-bay using this pin mapping.
2. Seagate NAS 2-bay/4-bay variants that include the same `seagate,dart-leds` DT node and equivalent pinctrl states.

If your board does not use the same DTS wiring (MPP and GPIO mapping), adapt the DTS before use.

## Driver Behavior Summary

From [linux/drivers/leds/leds-dart.c](linux/drivers/leds/leds-dart.c):

1. Registers LED class devices for SATA white LEDs.
2. Exposes a per-LED `sata` sysfs attribute.
3. Switches pinctrl state between:
: `default` (SATA mode)
: `gpio` (manual LED on/off)
4. Uses GPIO fallback when brightness is set to off.

The SATA controller support side is patched in `sata_mv` (SoC LED controller enable and presence indication bits).

## Upstream Status Note

The `sata_mv` change is being submitted upstream, so this repository currently keeps both pieces available until mainline includes the required behavior.

## Build Workflow (Repository)

1. Create/merge patches and compile binaries:

```bash
bash ./patch-compile.sh
```

2. Build `.deb` packages from `target/binaries`:

```bash
bash ./compiler/create-deb.sh
```

Output `.deb` files are written to `target/`.