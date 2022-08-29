#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Trimslice (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/trimslice/
#

# Hardware model
hw_model=${hw_model:-"trimslice"}

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
status_stage3 'Install kernel and u-boot packages'
eatmydata apt-get install -y linux-image-armmp u-boot-menu

status_stage3 'Copy rpi services'
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyS0 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
status "Creating image file ${image_name}.img"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary ext2 1MiB ${bootsize}MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype ${bootsize}MiB 100%

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
mkdir -p "${base_dir}"/root/boot
mount ${bootp} "${base_dir}"/root/boot

status "Fix root entry in extlinux.conf"

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
sed -i -e "0,/root=.*/s//root=UUID=$root_uuid rootfstype=$fstype console=ttyS0,115200 console=tty1 consoleblank=0 rw quiet rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf

# And we remove the "Debian GNU/Linux because we're Kali"
sed -i -e "s/Debian GNU\/Linux/Kali Linux/g" ${work_dir}/boot/extlinux/extlinux.conf

status "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/
sync

# Load default finish_image configs
include finish_image
