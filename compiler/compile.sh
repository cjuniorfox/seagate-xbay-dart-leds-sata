#!/bin/bash

LINUX_VERSION="${LINUX_VERSION:-6.12.107-1}"
LOCAL_VERSION="${LOCALVERSION:-+deb13-armmp}"
KERNEL_RELEASE="${LINUX_VERSION%-*}${LOCAL_VERSION}"

TARGET_PATCH_FILE="${TARGET_PATCH_FILE:-/patchfile.patch}"

echo "Installing compiling tools"

sed -i 's/^Types: deb$/Types: deb deb-src/g' /etc/apt/sources.list.d/debian.sources
dpkg --add-architecture armhf
apt-get update
apt-get install -y \
	bc \
	bison \
	dpkg-dev \
	file \
	flex \
	libssl-dev \
	gcc-arm-linux-gnueabihf \
	g++-arm-linux-gnueabihf \
	binutils-arm-linux-gnueabihf \
	xz-utils

arm-linux-gnueabihf-gcc --version

echo "Downloading proper linux headers"

apt-cache madison linux

useradd source -d /source
mkdir -p /source && chown source /source

su - source -c "
LINUX_VERSION='$LINUX_VERSION' \
LOCAL_VERSION='$LOCAL_VERSION' \
KERNEL_RELEASE='$KERNEL_RELEASE' \
TARGET_PATCH_FILE='$TARGET_PATCH_FILE' \
bash -s
" <<'EOF'
LINUX_SOURCE_DIR="/source/linux-${LINUX_VERSION%-*}"

cd /source

apt source "linux=$LINUX_VERSION"

apt download "linux-headers-$KERNEL_RELEASE"

mkdir -p /source/headers

dpkg-deb -x \
    "linux-headers-${KERNEL_RELEASE}_"*.deb \
    /source/headers

HEADER_DIR="$(find /source/headers/usr/src \
    -maxdepth 1 \
    -type d \
    -name "linux-headers-${KERNEL_RELEASE}" \
    -print -quit)"

if [ -z "$HEADER_DIR" ]; then
    echo "ERROR: kernel headers directory not found"
    exit 1
fi

test -f "$HEADER_DIR/.config" || {
    echo "ERROR: .config not found in Debian headers package"
    exit 1
}

test -f "$HEADER_DIR/Module.symvers" || {
    echo "ERROR: Module.symvers not found in Debian headers package"
    exit 1
}

cp "$HEADER_DIR/.config" "$LINUX_SOURCE_DIR/.config"
cp "$HEADER_DIR/Module.symvers" "$LINUX_SOURCE_DIR/Module.symvers"

cd "$LINUX_SOURCE_DIR"

patch -p1 < "$TARGET_PATCH_FILE"

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export LOCALVERSION="$LOCAL_VERSION"

./scripts/config --module CONFIG_SATA_MV
./scripts/config --module CONFIG_LEDS_DART

make olddefconfig

ACTUAL_RELEASE="$(make -s kernelrelease)"

if [ "$ACTUAL_RELEASE" != "$KERNEL_RELEASE" ]; then
    echo "ERROR: kernel release mismatch"
    echo "Expected: $KERNEL_RELEASE"
    echo "Actual:   $ACTUAL_RELEASE"
    exit 1
fi

make prepare
make scripts
make modules_prepare

make -j"$(nproc)" M=drivers/ata
make -j"$(nproc)" M=drivers/leds
make -j"$(nproc)" marvell/armada-370-seagate-nas-4bay.dtb
EOF

mkdir -p /target/binaries/drivers/ata
mkdir -p /target/binaries/drivers/leds
mkdir -p /target/binaries/arch/arm/boot/dts/marvell/

xz -c -1 --check=crc32 \
	/source/linux-${LINUX_VERSION%-*}/drivers/ata/sata_mv.ko \
	> /target/binaries/drivers/ata/sata_mv.ko.xz

xz -c -1 --check=crc32 \
	/source/linux-${LINUX_VERSION%-*}/drivers/leds/leds-dart.ko \
	> /target/binaries/drivers/leds/leds-dart.ko.xz

cp /source/linux-${LINUX_VERSION%-*}/arch/arm/boot/dts/marvell/armada-370-seagate-nas-4bay.dtb \
	/target/binaries/arch/arm/boot/dts/marvell/armada-370-seagate-nas-4bay.dtb
