#!/bin/bash

LINUX_VERSION="${LINUX_VERSION:-6.12.107-1}"
TARGET_PATCH_FILE="${TARGET_PATCH_FILE:-/patchfile.patch}"

echo "Installing compiling tools"

sed -i 's/^Types: deb$/Types: deb deb-src/g' /etc/apt/sources.list.d/debian.sources
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

apt-cache madison linux

useradd source -d /source
mkdir -p /source && chown source /source

su - source << EOF
cd /source
apt source linux=$LINUX_VERSION

cd /source/linux-${LINUX_VERSION%-*}

patch -p1 < "${TARGET_PATCH_FILE}"
cp /linux/Module.symvers ./Module.symvers
cp /linux/.config ./.config 

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export LOCALVERSION=+deb13-armmp

./scripts/config --module CONFIG_SATA_MV
./scripts/config --module CONFIG_LEDS_DART

make oldconfig
make prepare
make scripts
make modules_prepare

make -j$(nproc) M=drivers/ata
make -j$(nproc) M=drivers/leds
make -j$(nproc) marvell/armada-370-seagate-nas-4bay.dtb
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
