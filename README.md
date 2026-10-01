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
