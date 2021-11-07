#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Banana Pi (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/banana-pi/
#

# Hardware model
hw_model=${hw_model:-"banana-pi"}
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
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Copy rpi services'
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Install the kernel packages'
eatmydata apt-get install -y linux-image-armmp u-boot-menu u-boot-sunxi

status_stage3 'Load the ethernet module since it does not load automatically at boot'
echo "sunxi_emac" >> /etc/modules

status_stage3 'Create xorg config snippet to use fbdev driver'
mkdir -p /etc/X11/xorg.conf.d/
cp /bsp/xorg/20-fbdev.conf /etc/X11/xorg.conf.d/

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyS0 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype 4MiB 100%

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
echo 'U_BOOT_MENU_LABEL="Kali Linux"' >> ${work_dir}/etc/default/u-boot
echo 'U_BOOT_PARAMETERS="console=tty1 consoleblank=0 ro rootwait"' >> ${work_dir}/etc/default/u-boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/
sync

status "dd to ${loopdevice} (u-boot bootloader)"
dd if=${work_dir}/usr/lib/u-boot/Bananapi/u-boot-sunxi-with-spl.bin of=${loopdevice} bs=1024 seek=8

# Load default finish_image configs
include finish_image
