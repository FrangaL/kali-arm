#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Mini-X (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/mini-x/
#

# Hardware model
hw_model=${hw_model:-"mini-x"}
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
cat << EOF >>  ${work_dir}/third-stage
status_stage3 "Install kernel"
eatmydata apt-get install linux-image-armmp u-boot-menu u-boot-sunxi

# Note: This just creates an empty /boot/extlinux/extlinux.conf for us to use # later.
status_stage3 'Run u-boot-update'
u-boot-update

# We replace the u-boot menu defaults here so we can make sure the build system doesn't poison it
# We use _EOF_ so that the third-stage script doesn't end prematurely
mkdir -p /etc/default/u-boot
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=$fstype net.ifnames=0"
_EOF_


EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Build system will insert it's root filesystem into the extlinux.conf file so
# we sed it out, this only affects build time, not upgrading the kernel on the
# device itself
sed -i -e 's/append.*/append console=ttyS0,115200 console=tty1 root=\/dev\/mmcblk0p1 rootwait panic=10 rw rootfstype=$fstype net.ifnames=0/g' ${work_dir}/boot/extlinux/extlinux.conf

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
echo "Creating image file ${image_name}.img"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype 4MiB 100%

# Set the partition variables
make_loop
# Create file systems
mkfs_partitions
# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

# Write bootloader to imagefile
dd if=${work_dir}/usr/lib/u-boot/Mini-X/u-boot-sunxi-with-spl.bin of=${loopdevice} bs=1024 seek=8

# Load default finish_image configs
include finish_image
