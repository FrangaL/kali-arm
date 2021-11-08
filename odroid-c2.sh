#!/usr/bin/env bash
#
# Kali Linux ARM build-script for ODROID-C2 (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/odroid-c2/
#

# Hardware model
hw_model=${hw_model:-"odroid-c2"}
# Architecture
architecture=${architecture:-"arm64"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
add_interface eth0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Copy odroid-c2 services'
cp -p /bsp/services/odroid-c2/*.service /etc/systemd/system/

# For some reason the latest modesetting driver (part of xorg server) seems to cause a lot of jerkiness
status_stage3 'Using the fbdev driver is not ideal but it is far less frustrating to work with'
mkdir -p /etc/X11/xorg.conf.d
cp -p /bsp/xorg/20-meson.conf /etc/X11/xorg.conf.d/

status_stage3 'Install the kernel packages'
eatmydata apt-get install -y dkms linux-image-arm64 u-boot-menu

# We will replace this later, via sed, to point to the correct root partition (hopefully?)
status_stage3 'Run u-boot-update to generate the extlinux.conf file'
u-boot-update

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# 1366x768 is sort of broken on the ODROID-C2, not sure where the issue is, but
# we can work around it by setting the resolution to 1360x768
# This requires 2 files, a script and then something for lightdm to use
# I do not have anything set up for the console though, so that's still broken for now
mkdir -p ${work_dir}/usr/local/bin
cat << EOF > ${work_dir}/usr/local/bin/xrandrscript.sh
#!/usr/bin/env bash

resolution=$(xdpyinfo | awk '/dimensions:/ { print $2; exit }')

if [[ "$resolution" == "1366x768" ]]; then
    xrandr --newmode "1360x768_60.00"   84.75  1360 1432 1568 1776  768 771 781 798 -hsync +vsync
    xrandr --addmode HDMI-1 1360x768_60.00
    xrandr --output HDMI-1 --mode  1360x768_60.00
fi
EOF
chmod 0755 ${work_dir}/usr/local/bin/xrandrscript.sh

mkdir -p ${work_dir}/usr/share/lightdm/lightdm.conf.d/
cat << EOF > ${work_dir}/usr/share/lightdm/lightdm.conf.d/60-xrandrscript.conf
[SeatDefaults]
display-setup-script=/usr/local/bin/xrandrscript.sh
session-setup-script=/usr/local/bin/xrandrscript.sh
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
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# We are gonna use as much open source as we can here, hopefully we end up with a nice
# mainline u-boot and signed bootloader - unfortunately, due to the way this is packaged up
# we have to clone two different u-boot repositories - the one from HardKernel which
# has the bootloader binary blobs we need, and the denx mainline u-boot repository
# Let the fun begin

# Unset these because we're building on the host
unset ARCH
unset CROSS_COMPILE

status "Bootloader"
mkdir -p ${base_dir}/bootloader
cd ${base_dir}/bootloader
git clone --depth 1 https://github.com/afaerber/meson-tools --depth 1
git clone --depth 1 https://github.com/u-boot/u-boot.git
git clone --depth 1 https://github.com/hardkernel/u-boot -b odroidc2-v2015.01 u-boot-hk

# First things first, let's build the meson-tools, of which, we only really need amlbootsig
cd ${base_dir}/bootloader/meson-tools/
make
# Now we need to build fip_create
cd ${base_dir}/bootloader/u-boot-hk/tools/fip_create
HOSTCC=cc HOSTLD=ld make

cd ${base_dir}/bootloader/u-boot/
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- odroid-c2_defconfig
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu-

# Now the real fun... keeping track of file locations isn't fun, and i should probably move them to
# one single directory, but since we're not keeping these things around afterwards, it's fine to
# leave them where they are
# See:
# https://forum.odroid.com/viewtopic.php?t=26833
# https://github.com/nxmyoz/c2-overlay/blob/master/Readme.md
# for the inspirations for it.  Specifically Adrian's posts got us closest

# This is funky, but in the end, it should do the right thing
cd ${base_dir}/bootloader/
# Create the fip.bin
./u-boot-hk/tools/fip_create/fip_create --bl30 ./u-boot-hk/fip/gxb/bl30.bin \
--bl301 ./u-boot-hk/fip/gxb/bl301.bin --bl31 ./u-boot-hk/fip/gxb/bl31.bin \
--bl33 u-boot/u-boot.bin fip.bin

# Create the stage2 bootloader thingie?
cat ./u-boot-hk/fip/gxb/bl2.package fip.bin > boot_new.bin
# Now sign it, and call it u-boot.bin
./meson-tools/amlbootsig boot_new.bin u-boot.bin
# Now strip a portion of it off, and put it in the sd_fuse directory
dd if=u-boot.bin of=./u-boot-hk/sd_fuse/u-boot.bin bs=512 skip=96
# Finally, write it to the loopdevice so we have our bootloader on the card
cd ./u-boot-hk/sd_fuse
./sd_fusing.sh ${loopdevice}
sync

cd "${repo_dir}/"

# Load default finish_image configs
include finish_image
