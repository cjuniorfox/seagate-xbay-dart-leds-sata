#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="/target"
BINARY_ROOT="/target/binaries"

ARCH="armhf"
KERNEL_VERSION="${KERNEL_VERSION:-${LINUX_VERSION:-}}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

apt-get update
apt-get install -y --no-install-recommends \
    dpkg \
    xz-utils \
    coreutils

SATA_MODULE="${BINARY_ROOT}/drivers/ata/sata_mv.ko.xz"
LEDS_MODULE="${BINARY_ROOT}/drivers/leds/leds-dart.ko.xz"
DTB_FILE="${BINARY_ROOT}/arch/arm/boot/dts/marvell/armada-370-seagate-nas-4bay.dtb"

[ -f "${SATA_MODULE}" ] || die "Missing module: ${SATA_MODULE}"
[ -f "${LEDS_MODULE}" ] || die "Missing module: ${LEDS_MODULE}"
[ -f "${DTB_FILE}" ] || die "Missing DTB: ${DTB_FILE}"

if [ -z "${KERNEL_VERSION}" ]; then
    if command -v modinfo >/dev/null 2>&1; then
        tmp_mod="$(mktemp)"
        trap 'rm -f "${tmp_mod}"' EXIT
        xz -dc "${SATA_MODULE}" > "${tmp_mod}"
        KERNEL_VERSION="$(modinfo -F vermagic "${tmp_mod}" 2>/dev/null | awk '{print $1}')"
        rm -f "${tmp_mod}"
        trap - EXIT
    fi
fi

[ -n "${KERNEL_VERSION}" ] || die "Could not detect kernel version from module. Export KERNEL_VERSION or LINUX_VERSION."

PKG_VERSION="${KERNEL_VERSION}"

BUILD_ROOT="$(mktemp -d)"
SATA_PKG_NAME="linux-modules-sata-mv-seagate-nas-xbay"
LEDS_PKG_NAME="linux-modules-leds-dart-seagate-nas-xbay"

cleanup() {
    rm -rf "${BUILD_ROOT}"
}
trap cleanup EXIT

create_maintainer_scripts() {
    pkg_root="$1"

    cat > "${pkg_root}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

KERNEL_VERSION="${KERNEL_VERSION}"

if command -v depmod >/dev/null 2>&1; then
    depmod "$KERNEL_VERSION" || true
fi

if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k "$KERNEL_VERSION" || true
fi

exit 0
EOF

    sed -i "s/\${KERNEL_VERSION}/${KERNEL_VERSION}/g" "${pkg_root}/DEBIAN/postinst"
    chmod 0755 "${pkg_root}/DEBIAN/postinst"

    cat > "${pkg_root}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

KERNEL_VERSION="${KERNEL_VERSION}"

if command -v depmod >/dev/null 2>&1; then
    depmod "$KERNEL_VERSION" || true
fi

if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k "$KERNEL_VERSION" || true
fi

exit 0
EOF

    sed -i "s/\${KERNEL_VERSION}/${KERNEL_VERSION}/g" "${pkg_root}/DEBIAN/postrm"
    chmod 0755 "${pkg_root}/DEBIAN/postrm"
}

build_sata_package() {
    pkg_root="${BUILD_ROOT}/${SATA_PKG_NAME}_${PKG_VERSION}"
    deb_path="${TARGET_DIR}/${SATA_PKG_NAME}_${PKG_VERSION}_${ARCH}.deb"

    mkdir -p "${pkg_root}/DEBIAN"
    mkdir -p "${pkg_root}/lib/modules/${KERNEL_VERSION}/kernel/drivers/ata"

    install -m 0644 "${SATA_MODULE}" "${pkg_root}/lib/modules/${KERNEL_VERSION}/kernel/drivers/ata/sata_mv.ko.xz"

    cat > "${pkg_root}/DEBIAN/control" <<EOF
Package: ${SATA_PKG_NAME}
Version: ${PKG_VERSION}
Section: kernel
Priority: optional
Architecture: ${ARCH}
Maintainer: Seagate NAS XBAY Builder <root@localhost>
Depends: kmod, initramfs-tools
Description: Seagate NAS XBAY sata_mv kernel module
 Installs patched sata_mv kernel module for Seagate NAS.
EOF

    create_maintainer_scripts "${pkg_root}"
    dpkg-deb --build "${pkg_root}" "${deb_path}"
    echo "Created package: ${deb_path}"
}

build_leds_package() {
    pkg_root="${BUILD_ROOT}/${LEDS_PKG_NAME}_${PKG_VERSION}"
    deb_path="${TARGET_DIR}/${LEDS_PKG_NAME}_${PKG_VERSION}_${ARCH}.deb"

    mkdir -p "${pkg_root}/DEBIAN"
    mkdir -p "${pkg_root}/lib/modules/${KERNEL_VERSION}/kernel/drivers/leds"
    mkdir -p "${pkg_root}/boot/dtb-${KERNEL_VERSION}/marvell"

    install -m 0644 "${LEDS_MODULE}" "${pkg_root}/lib/modules/${KERNEL_VERSION}/kernel/drivers/leds/leds-dart.ko.xz"
    install -m 0644 "${DTB_FILE}" "${pkg_root}/boot/dtb-${KERNEL_VERSION}/marvell/armada-370-seagate-nas-4bay.dtb"

    cat > "${pkg_root}/DEBIAN/control" <<EOF
Package: ${LEDS_PKG_NAME}
Version: ${PKG_VERSION}
Section: kernel
Priority: optional
Architecture: ${ARCH}
Maintainer: Seagate NAS XBAY Builder <root@localhost>
Depends: kmod, initramfs-tools
Description: Seagate NAS XBAY leds-dart module and DTB
 Installs leds-dart kernel module and Seagate NAS 4-bay DTB.
EOF

    create_maintainer_scripts "${pkg_root}"
    dpkg-deb --build "${pkg_root}" "${deb_path}"
    echo "Created package: ${deb_path}"
}

mkdir -p "${TARGET_DIR}"
build_sata_package
build_leds_package

echo "Package version: ${PKG_VERSION}"
echo "Kernel version used: ${KERNEL_VERSION}"

