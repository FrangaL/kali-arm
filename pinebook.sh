#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Pinebook (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/pinebook/
#

# Hardware model
hw_model=${hw_model:-"pinebook"}
# Architecture
architecture=${architecture:-"arm64"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
#add_interface eth0

# Do not include wlan0 on a wireless only device, otherwise NetworkManager won't run
# wlan0 requires special editing of the /etc/network/interfaces.d/wlan0 file, to add the wireless network and ssid
# Network configs
#add_interface wlan0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Copy rpi services'
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Install the kernel packages'
eatmydata apt-get install -y dkms linux-headers-arm64 linux-image-arm64 u-boot-menu u-boot-sunxi

# Note: This just creates an empty /boot/extlinux/extlinux.conf for us to use
# later.
status_stage3 'Run u-boot-update'
u-boot-update

status_stage3 'Install touchpad config file'
install -m644 /bsp/xorg/50-pine64-pinebook.touchpad.conf /etc/X11/xorg.conf.d/

status_stage3 'Add wifi firmware and driver, and attempt to build'
# so we don't need to build on first boot, which causes issues if people log in too soon
# Pull in the wifi and bluetooth firmware from anarsoul's git repository
git clone https://github.com/anarsoul/rtl8723bt-firmware
cd rtl8723bt-firmware
cp -a rtl_bt /lib/firmware/

status_stage3 'Need to package up the wifi driver'
# (it's a Realtek 8723cs, with the usual Realtek driver quality) still,
# so for now, we clone it and then build it inside the chroot
cd /usr/src/
git clone https://github.com/icenowy/rtl8723cs -b new-driver-by-megous rtl8723cs-2020.02.27
cat << __EOF__ > /usr/src/rtl8723cs-2020.02.27/dkms.conf
PACKAGE_NAME="rtl8723cs"
PACKAGE_VERSION="2020.02.27"

AUTOINSTALL="yes"

CLEAN[0]="make clean"

MAKE[0]="'make' -j4 ARCH=arm64 KVER=5.14.0-kali4-arm64 KSRC=/lib/modules/5.14.0-kali4-arm64/build/"

BUILT_MODULE_NAME[0]="8723cs"

BUILT_MODULE_LOCATION[0]=""

DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
__EOF__

cd /usr/src/rtl8723cs-2020.02.27
# 5.14+ warns about reproducable builds, so we remove the date and time of the driver build
# as warnings are also now errors.
sed -i '50d' core/rtw_debug.c
dkms install rtl8723cs/2020.02.27 -k 5.14.0-kali4-arm64

status_stage3 'Replace the conf file after we have built the module and hope for the best'
cp /bsp/configs/pinebook-dkms.conf /usr/src/rtl8723cs-2020.02.27/dkms.conf

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Set up some defaults for chromium, if the user ever installs it
status "Set default chromium options"
mkdir -p ${work_dir}/etc/chromium/
cat << EOF > ${work_dir}/etc/chromium/default
#Options to pass to chromium
CHROMIUM_FLAGS="\
--disable-smooth-scrolling \
--disable-low-res-tiling \
--enable-low-end-device-mode \
--num-raster-threads=\$(nproc) \
--profiler-timing=0 \
--disable-composited-antialiasing \
"
EOF

cd "${repo_dir}/"

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
mount "${rootp}" "${base_dir}"/root


# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
status "Edit the extlinux.conf file to set root uuid and proper name"
sed -i -e "0,/root=.*/s//root=UUID=$root_uuid rootfstype=$fstype console=tty1 consoleblank=0 ro rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf
# And we remove the "GNU/Linux because we don't use it
sed -i -e "s|.*GNU/Linux Rolling|menu label Kali Linux|g" ${work_dir}/boot/extlinux/extlinux.conf

status "Set the default options in /etc/default/u-boot"
echo 'U_BOOT_MENU_LABEL="Kali Linux"' >> ${work_dir}/etc/default/u-boot
echo 'U_BOOT_PARAMETERS="console=tty1 consoleblank=0 ro rootwait"' >> ${work_dir}/etc/default/u-boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# Adapted from the u-boot-install-sunxi64 script
status "Write u-boot bootloader to the image file" # Note: do not write to the actual image file, but to the loop device, otherwise you will overwite what is in the image.
dd conv=notrunc if=${work_dir}/usr/lib/u-boot/pinebook/sunxi-spl.bin of=${loopdevice} bs=8k seek=1
dd conv=notrunc if=${work_dir}/usr/lib/u-boot/pinebook/u-boot-sunxi-with-spl.fit.itb of=${loopdevice} bs=8k seek=5
sync

# Load default finish_image configs
include finish_image
