#!/usr/bin/env bash
#
# Kali Linux ARM build-script for CuBox-i4Pro (32-bit) - Freescale based NOT the original Marvell based
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/cubox-i4pro/
#

# Hardware model
hw_model=${hw_model:-"cubox-i4pro"}

# Architecture
architecture=${architecture:-"armhf"}

# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
add_interface eth0

# Third stage
cat <<EOF >>"${work_dir}"/third-stage
status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttymxc0 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# For some reason the brcm firmware doesn't work properly in linux-firmware git
# so we grab the ones from OpenELEC
cd ${base_dir}
git clone https://github.com/OpenELEC/wlan-firmware
cd wlan-firmware
rm -rf ${work_dir}/lib/firmware/brcm
cp -a firmware/brcm ${work_dir}/lib/firmware/

cd "${repo_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary "$fstype" 4MiB 100%

# Set the partition variables
make_loop

# Create file systems
mkfs_partitions

# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

status "Edit the extlinux.conf file to set root uuid and proper name"

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
sed -i -e "0,/root=.*/s//root=UUID=$root_uuid rootfstype=$fstype console=tty1 consoleblank=0 ro rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf

# And we remove the "GNU/Linux because we don't use it
sed -i -e "s|.*GNU/Linux Rolling|menu label Kali Linux|g" ${work_dir}/boot/extlinux/extlinux.conf

status "Set the default options in /etc/default/u-boot"
echo 'U_BOOT_MENU_LABEL="Kali Linux"' >>${work_dir}/etc/default/u-boot
echo 'U_BOOT_PARAMETERS="console=tty1 consoleblank=0 ro rootwait"' >>${work_dir}/etc/default/u-boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/
sync

status "dd to ${loopdevice} (u-boot bootloader)"
dd conv=fsync,notrunc if=${work_dir}/usr/lib/u-boot/mx6cuboxi/SPL of=${loopdevice} bs=1k seek=1
dd conv=fsync,notrunc if=${work_dir}/usr/lib/u-boot/mx6cuboxi/u-boot.img of=${loopdevice} bs=1k seek=69

# Load default finish_image configs
include finish_image
