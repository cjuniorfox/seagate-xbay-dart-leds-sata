# Patch for drivers on Seagate NAS 4-bay

## Create the patch files

### 1. Create patch for sata-mv

```bash
truncate -s 0 ./patcher/0001-ata-sata_mv-enable-SoC-SATA-LED-presence-indication.patch
podman run \
    --rm \
    -v ./patcher/create-patch.sh:/create-patch.sh \
    -v ./patcher/0001-sata_mv.txt:/patch-files.txt \
    -v ./patcher/0001-ata-sata_mv-enable-SoC-SATA-LED-presence-indication.patch:/patchfile.patch \
    -v ./linux/:/linux/ \
    --entrypoint=sh debian:13 \
    /create-patch.sh
```

### 2. Create patch for dart-leds

```bash
truncate -s 0 ./patcher/0002-leds-dart-add-Seagate-Dart-NAS-LED-driver.patch
podman run \
    --rm \
    -v ./patcher/create-patch.sh:/create-patch.sh \
    -v ./patcher/0002-leds-dart.txt:/patch-files.txt \
    -v ./patcher/0002-leds-dart-add-Seagate-Dart-NAS-LED-driver.patch:/patchfile.patch \
    -v ./linux/:/linux/ \
    --entrypoint=sh debian:13 \
    /create-patch.sh
```

### 3. Merge patched files

```bash
cat ./patcher/0001-ata-sata_mv-enable-SoC-SATA-LED-presence-indication.patch \
    ./patcher/0002-leds-dart-add-Seagate-Dart-NAS-LED-driver.patch \
    > ./0001-full-patch.patch
```

### 4. Compile kernel binaries

```bash
podman run \
    --rm \
    -v ./compiler/compile.sh:/compile.sh \
    -v ./0001-full-patch.patch:/patchfile.patch \
    -v ./target/:/target/ \
    --entrypoint=sh debian:13 \
    /compile.sh
```

### 5. Build a .deb from target binaries

After compiling, package the generated modules and DTB into Debian packages:

```bash
bash ./compiler/create-deb.sh
```

This script uses fixed paths inside the Debian container:

- Source root: `/target/binaries`
- Output directory: `/target`
- Package 1: `linux-modules-sata-mv-seagate-nas-xbay` (contains `sata_mv.ko.xz`)
- Package 2: `linux-modules-leds-dart-seagate-nas-xbay` (contains `leds-dart.ko.xz` and DTB)

Each package has independent `postinst` and `postrm` hooks that run `depmod` and `update-initramfs` for the kernel version.

The package version is the same as the kernel version from `KERNEL_VERSION` (or `LINUX_VERSION`), and both output packages are created in `./target/`.