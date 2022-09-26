#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Pinebook Pro (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/pinebook-pro/
#

# Hardware model
hw_model=${hw_model:-"pinebook-pro"}

# Architecture
architecture=${architecture:-"arm64"}

# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Do *NOT* include wlan0 if using a desktop otherwise NetworkManager will ignore it
# Network configs
basic_network
#add_interface wlan0

# Third stage
cat <<EOF >>"${work_dir}"/third-stage
# Do not install firmware-brcm80211, the firmware in upstream causes kernel panics.
# We use the one that armbian has in their repository at
# https://github.com/armbian/firmware/
# It uses the 43456 files.
eatmydata apt-get install -y dkms kali-sbc-rockchip linux-image-arm64

status_stage3 'Touchpad settings'
mkdir -p /etc/X11/xorg.conf.d/
install -m644 /bsp/xorg/50-pine64-pinebook-pro.touchpad.conf /etc/X11/xorg.conf.d/

status_stage3 'Saved audio settings'
# Create the directory first, it won't exist if there is no desktop installed because alsa isn't installed.
mkdir -p /var/lib/alsa/
install -m644 /bsp/audio/pinebook-pro/asound.state /var/lib/alsa/asound.state

status_stage3 'Enable bluetooth'
systemctl enable bluetooth

status_stage3 'Enable suspend2idle'
sed -i s/"#SuspendState=mem standby freeze"/"SuspendState=freeze"/g /etc/systemd/sleep.conf

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream

status_stage3 'Add in 43455 firmware for newer model Pinebook Pro'
mkdir -p /lib/firmware/brcm/
cp -a /bsp/firmware/pbp/* /lib/firmware/brcm/
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Pull in the wifi and bluetooth firmware from Armbian's git repository
cd "${work_dir}"/
git clone --depth 1 https://github.com/armbian/firmware.git
cd firmware/
mkdir -p "${work_dir}"/lib/firmware/brcm/
cp brcm/BCM4345C5.hcd "${work_dir}"/lib/firmware/brcm/BCM4345C5.hcd
cp brcm/brcmfmac43456-sdio.txt "${work_dir}"/lib/firmware/brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt
cp brcm/brcmfmac43456-sdio.bin "${work_dir}"/lib/firmware/brcm/brcmfmac43456-sdio.bin
cp brcm/brcmfmac43456-sdio.clm_blob "${work_dir}"/lib/firmware/brcm/brcmfmac43456-sdio.clm_blob
cd "${repo_dir}/"
rm -rf "${work_dir}"/firmware

# Enable brightness up/down and sleep hotkeys and attempt to improve
# touchpad performance
status "Keyboard hotkeys"
mkdir -p "${work_dir}"/etc/udev/hwdb.d/
cat <<EOF >"${work_dir}"/etc/udev/hwdb.d/10-usb-kbd.hwdb
evdev:input:b0003v258Ap001E*
KEYBOARD_KEY_700a5=brightnessdown
KEYBOARD_KEY_700a6=brightnessup
KEYBOARD_KEY_70066=sleep
EVDEV_ABS_00=::15
EVDEV_ABS_01=::15
EVDEV_ABS_35=::15
EVDEV_ABS_36=::15
EOF

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype 32MiB 100%

# Set the partition variables
make_loop

# Create file systems
mkfs_partitions

# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/

if [[ $fstype == ext4 ]]; then
    mount -t ext4 -o noatime,data=writeback,barrier=0 "${rootp}" "${base_dir}"/root

else
    mount "${rootp}" "${base_dir}"/root

fi

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
status "Edit the extlinux.conf file to set root uuid and proper name"
sed -i -e "0,/root=.*/s//root=UUID=$root_uuid rootfstype=$fstype console=tty1 ro rootwait/g" "${work_dir}"/boot/extlinux/extlinux.conf

# And we remove the "GNU/Linux because we don't use it
sed -i -e "s|.*GNU/Linux Rolling|menu label Kali Linux|g" "${work_dir}"/boot/extlinux/extlinux.conf

status "Set the default options in /etc/default/u-boot"
echo 'U_BOOT_MENU_LABEL="Kali Linux"' >>"${work_dir}"/etc/default/u-boot
echo 'U_BOOT_PARAMETERS="console=tty1 ro rootwait"' >>"${work_dir}"/etc/default/u-boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# This comes from the u-boot-rockchip package which is installed into the image, and not the build machine
# which is why the target and call look weird; u-boot-install-rockchip is just a script calling dd with the
# right options and pointing to the correct files via TARGET.
status "dd to ${loopdevice} (u-boot bootloader)"
TARGET="${work_dir}/usr/lib/u-boot/pinebook-pro-rk3399" ${work_dir}/usr/bin/u-boot-install-rockchip ${loopdevice}

# Load default finish_image configs
include finish_image
