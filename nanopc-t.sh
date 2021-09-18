#!/usr/bin/env bash
#
# Kali Linux ARM build-script for NanoPC-T3/T4 (64-bit)
# https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images for
# More information: https://www.kali.org/docs/arm/nanopc-t3/
#

# Stop on error
set -e

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"nanopc-t"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load common variables
include variables
# Checks script environment
include check
# Packages build list
include packages
# Load automatic proxy configuration
include proxy_apt
# Execute initial debootstrap
debootstrap_exec http://http.kali.org/kali
# Enable eatmydata in compilation
include eatmydata
# debootstrap second stage
systemd-nspawn_exec eatmydata /debootstrap/debootstrap --second-stage
# Define sources.list
include sources.list
# APT options
include apt_options
# So X doesn't complain, we add kali to hosts
include hosts
# Set hostname
set_hostname "${hostname}"
# Network configs
include network
add_interface eth0
#add_interface wlan0

# Copy directory bsp into build dir
log "Copy directory bsp into build dir" green
cp -rp bsp "${work_dir}"

# Disable RESUME (suspend/resume is currently broken anyway!) which speeds up boot massively
mkdir -p ${work_dir}/etc/initramfs-tools/conf.d/
cat << EOF > ${work_dir}/etc/initramfs-tools/conf.d/resume
RESUME=none
EOF

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken

eatmydata apt-get -y --purge autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/

# Copy script rpi-resizerootfs
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

# Enable rpi-resizerootfs first boot
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

# Enable runonce
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

# Clean up dpkg.eatmydata
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 0755 "${work_dir}"/third-stage
log "Run third stage" green
systemd-nspawn_exec /third-stage

# Choose a locale
set_locale "$locale"
# Clean system
include clean_system
trap clean_build ERR SIGTERM SIGINT
# Define DNS server after last running systemd-nspawn
echo "nameserver ${nameserver}" > "${work_dir}"/etc/resolv.conf
# Disable the use of http proxy in case it is enabled
disable_proxy
# Mirror & suite replacement
restore_mirror
# Reload sources.list
#include sources.list

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
log "Kernel section" green
git clone --depth 1 https://github.com/friendlyarm/linux -b nanopi2-v4.4.y ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel/
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm64
#export CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
export CROSS_COMPILE=aarch64-linux-gnu-
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/kali-wifi-injection-4.4.patch
make nanopi3_linux_defconfig
make -j $(grep -c processor /proc/cpuinfo)
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm64/boot/Image ${work_dir}/boot
cp arch/arm64/boot/dts/nexell/*.dtb ${work_dir}/boot/
make mrproper
make nanopi3_linux_defconfig
cd "${current_dir}/"

# Copy over the firmware for the nanopi3 wifi
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon
log "WiFi firmware" green
mkdir -p ${work_dir}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${work_dir}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/config.txt
cd "${current_dir}/"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
log "building external modules" green
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}/
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${current_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
log "Create the disk partitions" green
parted -s "${current_dir}"/"${imagename}".img mklabel msdos
parted -s "${current_dir}"/"${imagename}".img mkpart primary ext3 4MiB "${bootsize}"MiB
parted -s -a minimal "${current_dir}"/"${imagename}".img mkpart primary "$fstype" "${bootsize}"MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
bootp="${loopdevice}p1"
rootp="${loopdevice}p2"

# Create file systems
log "Formatting partitions" green
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L BOOT "${bootp}"
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
log "Create the dirs for the partitions and mount them" green
mkdir -p "${basedir}"/root/
mount "${rootp}" "${basedir}"/root
mkdir -p "${basedir}"/root/boot
mount "${bootp}" "${basedir}"/root/boot

# We do this here because we don't want to hardcode the UUID for the partition during creation
# systemd doesn't seem to be generating the fstab properly for some people, so let's create one
log "/etc/fstab" green
cat <<EOF >"${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
UUID=$(blkid -s UUID -o value ${rootp})  /               $fstype    defaults,noatime  0       1
EOF

log "Rsyncing rootfs into image file" green
rsync -HPavz -q "${work_dir}"/ "${basedir}"/root/
sync

# Samsung bootloaders must be signed
# These are the same steps that are done by
# https://github.com/friendlyarm/sd-fuse_nanopi2/blob/master/fusing.sh
log "Samsung bootloaders" green
mkdir -p "${basedir}"/bootloader/
cd "${basedir}"/bootloader/
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/bl1-mmcboot.bin?raw=true' -O "${basedir}"/bootloader/bl1-mmcboot.bin
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-loader.img?raw=true' -O "${basedir}"/bootloader/fip-loader.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-secure.img?raw=true' -O "${basedir}"/bootloader/fip-secure.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/prebuilt/fip-nonsecure.img?raw=true' -O "${basedir}"/bootloader/fip-nonsecure.img
wget 'https://github.com/friendlyarm/sd-fuse_s5p6818/blob/master/tools/fw_printenv?raw=true' -O "${basedir}"/bootloader/fw_printenv
chmod 0755 "${basedir}"/bootloader/fw_printenv
ln -s "${basedir}"/bootloader/fw_printenv "${basedir}"/bootloader/fw_setenv

dd if="${basedir}"/bootloader/bl1-mmcboot.bin of=${loopdevice} bs=512 seek=1
dd if="${basedir}"/bootloader/fip-loader.img of=${loopdevice} bs=512 seek=129
dd if="${basedir}"/bootloader/fip-secure.img of=${loopdevice} bs=512 seek=769
dd if="${basedir}"/bootloader/fip-nonsecure.img of=${loopdevice} bs=512 seek=3841

cat << EOF > "${basedir}"/bootloader/env.conf
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

# It should be possible to build your own u-boot, as part of this, if you
# prefer, it will only generate the fip-nonsecure.img however
#git clone https://github.com/friendlyarm/u-boot -b nanopi2-v2016.01
#cd u-boot
#make CROSS_COMPILE=aarch64-linux-gnu- s5p6818_nanopi3_defconfig
#make CROSS_COMPILE=aarch64-linux-gnu-
#dd if=fip-nonsecure.img of=$loopdevice bs=512 seek=3841

cd "${current_dir}/"

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk.
blockdev --flushbufs "${loopdevice}"
python -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Umount filesystem
log "Umount filesystem" green
umount -l "${rootp}"

# Check filesystem
log "Check filesystem" green
e2fsck -y -f "$rootp"

# Remove loop devices
log "Remove loop devices" green
kpartx -dv "${loopdevice}" 
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories
# Comment this out to keep things around if you want to see what may have gone wrong
clean_build
