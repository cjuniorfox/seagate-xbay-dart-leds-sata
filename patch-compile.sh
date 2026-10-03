#!/bin/bash

LINUX_VERSION="${LINUX_VERSION:-6.12.111-1}"

podman run \
    --rm -i \
    -v ./patcher/:/patcher/ \
    -v ./compiler/:/compiler/ \
    -v ./linux:/linux/ \
    -v ./target/:/target/ \
    -e LINUX_VERSION="${LINUX_VERSION}" \
    --entrypoint=/bin/sh debian:13 << EOF

LINUX_VERSION="${LINUX_VERSION}"

echo "Creating patch file for sata_mv driver"
export TXT_PATCH_FILES="/patcher/0001-sata_mv.txt"
export TARGET_PATCH_FILE="/target/0001-ata-sata_mv-enable-SoC-SATA-LED-presence-indication.patch"
sh /patcher/create-patch.sh

echo "Creating patch file for leds-dart driver"
export TXT_PATCH_FILES="/patcher/0002-leds-dart.txt"
export TARGET_PATCH_FILE="/target/0002-leds-dart-enable-SoC-SATA-LED-presence-indication.patch"
sh /patcher/create-patch.sh

echo "Merge patches into a single patch file"
truncate -s 0 /target/0003-merge-patches.patch
cat /target/0001-ata-sata_mv-enable-SoC-SATA-LED-presence-indication.patch >> /target/0003-merge-patches.patch
cat /target/0002-leds-dart-enable-SoC-SATA-LED-presence-indication.patch >> /target/0003-merge-patches.patch

echo "Compile the kernel drivers with the merged patch file"

export TARGET_PATCH_FILE="/target/0003-merge-patches.patch"
sh /compiler/compile.sh

echo "Create deb package for the compiled drivers"
export SATA_PKG_NAME="linux-modules-sata-mv-seagate-nas-xbay"
export LEDS_PKG_NAME="linux-modules-leds-dart-seagate-nas-xbay"
export TARGET_DIR="/target"
sh /compiler/create-deb.sh

EOF