#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Radxa Zero (64 bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/radxa-zero/
#

# Hardware model
hw_model=${hw_model:-"radxa-zero-emmc"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Install u-boot-menu'
eatmydata apt-get install -y u-boot-menu

# Note: This just creates an empty /boot/extlinux/extlinux.conf for us to use 
# later when we install the kernel, and then fixup further down
status_stage3 'Run u-boot-update'
u-boot-update

status_stage3 'Copy WiFi/BT firmware'
mkdir -p /lib/firmware/brcm/
cp /bsp/firmware/radxa-zero/* /lib/firmware/brcm/
EOF

# Run third stage
include third_stage

# Clean system
include clean_system
trap clean_build ERR SIGTERM SIGINT

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
status "Kernel stuff"
git clone --depth 1 -b linux-5.10.y-radxa-zero https://github.com/radxa/kernel.git ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
rm -rf .git
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/kali-wifi-injection-5.9.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make radxa_zero_defconfig
make -j $(grep -c processor /proc/cpuinfo) LOCALVERSION="" bindeb-pkg
make mrproper
make radxa_zero_defconfig
cd ..
# Cross building kernel packages produces broken header packages
# so only install the headers if we're building on arm64
if [ "$(arch)" == 'aarch64' ]; then
  dpkg --root "${work_dir}" -i linux-*.deb
else
  dpkg --root "${work_dir}" -i linux-image-*.deb
fi
rm linux-*_*

cd "${repo_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary ext2 4MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${image_dir}/${image_name}.img")
rootp="${loopdevice}p1"

# Create file systems
status "Formatting partitions"
mkfs.ext2 ${rootp}

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

# Create an fstab so that we don't mount / read-only
status "/etc/fstab"
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

status "Edit the extlinux.conf file to set root uuid and proper name"
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
sed -i -e "0,/append.*/s//append root=UUID=$(blkid -s UUID -o value ${rootp}) rootfstype=$fstype earlyprintk console=ttyAML0,115200 console=tty1 swiotlb=1 coherent_pool=1m ro rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf
# And we remove the "GNU/Linux because we don't use it
sed -i -e "s|.*GNU/Linux Rolling|menu label Kali Linux|g" ${work_dir}/boot/extlinux/extlinux.conf

status "Set the default options in /etc/default/u-boot"
echo 'U_BOOT_MENU_LABEL="Kali Linux"' >> ${work_dir}/etc/default/u-boot
echo 'U_BOOT_PARAMETERS="earlyprintk console=ttyAML0,115200 console=tty1 swiotlb=1 coherent_pool=1m ro rootwait"' >> ${work_dir}/etc/default/u-boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

status "u-Boot"
cd "${work_dir}"
git clone https://github.com/radxa/fip.git
git clone https://github.com/radxa/u-boot.git --depth 1 -b radxa-zero-v2021.07
cd u-boot
make distclean
make radxa-zero_config
make ARCH=arm -j$(nproc)
cp u-boot.bin ../fip/radxa-zero/bl33.bin
cd ../fip/radxa-zero/
make
# https://wiki.radxa.com/Zero/dev/u-boot
dd if=u-boot.bin of=${loopdevice} conv=fsync,notrunc bs=1 count=444
dd if=u-boot.bin of=${loopdevice} conv=fsync,notrunc bs=512 skip=1 seek=1
cd "${repo_dir}/"
rm -rf "${work_dir}"/{fip,u-boot}

# Load default finish_image configs
include finish_image
