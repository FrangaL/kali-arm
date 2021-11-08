#!/usr/bin/env bash
#
# Kali Linux ARM build-script for NanoPC-T3/T4 (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/nanopc-t3/
#

# Hardware model
hw_model=${hw_model:-"nanopc-t"}
# Architecture
architecture=${architecture:-"arm64"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
add_interface eth0
#add_interface wlan0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
status "Kernel section"
git clone --depth 1 https://github.com/friendlyarm/linux -b nanopi2-v4.4.y ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel/
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm64
#export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
export CROSS_COMPILE=aarch64-linux-gnu-
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/kali-wifi-injection-4.4.patch
make nanopi3_linux_defconfig
make -j $(grep -c processor /proc/cpuinfo)
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm64/boot/Image ${work_dir}/boot
cp arch/arm64/boot/dts/nexell/*.dtb ${work_dir}/boot/
make mrproper
make nanopi3_linux_defconfig
cd "${repo_dir}/"

# Copy over the firmware for the nanopi3 wifi
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon
status "WiFi firmware"
mkdir -p ${work_dir}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${work_dir}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/config.txt
cd "${repo_dir}/"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
status "building external modules"
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}/
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${repo_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary ext3 4MiB "${bootsize}"MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary "$fstype" "${bootsize}"MiB 100%

# Set the partition variables
make_loop
# Create file systems
mkfs_partitions
# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/
mount "${rootp}" "${base_dir}"/root
mkdir -p "${base_dir}"/root/boot
mount "${bootp}" "${base_dir}"/root/boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# Samsung bootloaders must be signed
# These are the same steps that are done by
# https://github.com/friendlyarm/sd-fuse_nanopi2/blob/master/fusing.sh
status "Samsung bootloaders"
mkdir -p "${base_dir}"/bootloader/
cd "${base_dir}"/bootloader/
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/bl1-mmcboot.bin?raw=true' -O "${base_dir}"/bootloader/bl1-mmcboot.bin
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-loader.img?raw=true' -O "${base_dir}"/bootloader/fip-loader.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-secure.img?raw=true' -O "${base_dir}"/bootloader/fip-secure.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-nonsecure.img?raw=true' -O "${base_dir}"/bootloader/fip-nonsecure.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/tools/fw_printenv?raw=true' -O "${base_dir}"/bootloader/fw_printenv
chmod 0755 "${base_dir}"/bootloader/fw_printenv
ln -s "${base_dir}"/bootloader/fw_printenv "${base_dir}"/bootloader/fw_setenv

dd if="${base_dir}"/bootloader/bl1-mmcboot.bin of=${loopdevice} bs=512 seek=1
dd if="${base_dir}"/bootloader/fip-loader.img of=${loopdevice} bs=512 seek=129
dd if="${base_dir}"/bootloader/fip-secure.img of=${loopdevice} bs=512 seek=769
dd if="${base_dir}"/bootloader/fip-nonsecure.img of=${loopdevice} bs=512 seek=3841

cat << EOF > "${base_dir}"/bootloader/env.conf
# U-Boot environment for Debian, Ubuntu
#
# Copyright (C) Guangzhou FriendlyARM Computer Tech. Co., Ltd
# (http://www.friendlyarm.com)
#

bootargs	console=ttySAC0,115200n8 root=/dev/mmcblk0p2 rootfstype=$fstype rootwait rw consoleblank=0 net.ifnames=0
bootdelay	1
EOF

./fw_setenv ${loopdevice} -s env.conf
sync

cd "${repo_dir}/"

# It should be possible to build your own u-boot, as part of this, if you
# prefer, it will only generate the fip-nonsecure.img however
#git clone https://github.com/friendlyarm/u-boot -b nanopi2-v2016.01
#cd u-boot
#make CROSS_COMPILE=aarch64-linux-gnu- s5p6818_nanopi3_defconfig
#make CROSS_COMPILE=aarch64-linux-gnu-
#dd if=fip-nonsecure.img of=$loopdevice bs=512 seek=3841

# Load default finish_image configs
include finish_image
