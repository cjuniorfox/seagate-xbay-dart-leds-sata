#!/bin/bash

LINUX_VERSION="6.12.107-1"

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

useradd source
mkdir -p /target/linux && chown source /target/linux

su - source << EOF
cd /target/linux
apt source linux=6.12.107-1
EOF

truncate -s 0 /tmp/0001-patch.patch

while read file; do
	file_b="/linux/$file"
	label_b="b/$file"
	file_a="/target/linux/linux-${LINUX_VERSION%-*}/${file}"
	label_a="a/$file"
	if [ ! -f "$file_a" ]; then
		file_a=/dev/null
		label_a=/dev/null
	fi
	diff -u \
		--label "$label_a" \
		--label "$label_b" \
		"$file_a" "$file_b" \
		>> /patchfile.patch
done < patch-files.txt 

