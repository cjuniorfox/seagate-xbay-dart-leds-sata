#!/bin/bash

LINUX_VERSION="${LINUX_VERSION:-6.12.107-1}"
TXT_PATCH_FILES="${TXT_PATCH_FILES:-/patch-files.txt}"
TARGET_PATCH_FILE="${TARGET_PATCH_FILE:-/patchfile.patch}"

echo "Installing compiling tools"

sed -i 's/^Types: deb$/Types: deb deb-src/g' /etc/apt/sources.list.d/debian.sources
apt-get update
apt-get install -y \
	bison \
	dpkg-dev \
	file \
	flex \
	libssl-dev \
	gcc-arm-linux-gnueabihf \
	g++-arm-linux-gnueabihf \
	binutils-arm-linux-gnueabihf

arm-linux-gnueabihf-gcc --version

apt-cache madison linux

useradd source -d /source
mkdir -p /source && chown source /source

su - source << EOF
cd /source
apt source linux=$LINUX_VERSION
EOF

truncate -s 0 "$TARGET_PATCH_FILE"

while read file; do
	file_b="/linux/$file"
	label_b="b/$file"
	file_a="/source/linux-${LINUX_VERSION%-*}/${file}"
	label_a="a/$file"
	if [ ! -f "$file_a" ]; then
		file_a=/dev/null
		label_a=/dev/null
	fi
	diff -u \
		--label "$label_a" \
		--label "$label_b" \
		"$file_a" "$file_b" \
		| tee -a "$TARGET_PATCH_FILE"
done < "$TXT_PATCH_FILES" 

