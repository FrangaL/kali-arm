#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Gateworks Ventana (32-bit) - Freescale based
# https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images for
# More information: https://www.kali.org/docs/arm/gateworks-ventana/
#

# Stop on error
set -e

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"gateworks-ventana"}
# Architecture
architecture=${architecture:-"armhf"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load common variables
include variables
# Checks script enviroment
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
# Copy directory bsp into build dir.
cp -rp bsp "${work_dir}"

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken
# We run a dhcp server on the ventana so
eatmydata apt-get install -y isc-dhcp-server || eatmydata apt-get install -y --fix-broken

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
echo "T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

install -m644 /bsp/bootloader/gateworks-ventana/6x_bootscript-ventana.script /boot/6x_bootscript-ventana.script
mkimage -A arm -T script -C none -d /boot/6x_bootscript-ventana.script /boot/6x_bootscript-ventana

# Enable runonce
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

# Clean up dpkg.eatmydata
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 755 "${work_dir}"/third-stage
systemd-nspawn_exec /third-stage

# Choose a locale
set_locale "$locale"
# Clean system
include clean_system
# Define DNS server after last running systemd-nspawn.
echo "nameserver 8.8.8.8" >"${work_dir}"/etc/resolv.conf
# Disable the use of http proxy in case it is enabled.
disable_proxy
# Mirror & suite replacement
restore_mirror
# Reload sources.list
#include sources.list

# Set up usb gadget mode
cat << EOF > ${work_dir}/etc/dhcp/dhcpd.conf
ddns-update-style none;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet 10.10.10.0 netmask 255.255.255.0 {
        range 10.10.10.10 10.10.10.20;
        option subnet-mask 255.255.255.0;
        option domain-name-servers 8.8.8.8;
        option routers 10.10.10.1;
        default-lease-time 600;
        max-lease-time 7200;
}
EOF

echo | sed -e '/^#/d ; /^ *$/d' | systemd-nspawn_exec << EOF
#Setup Serial Port
#echo 'g_cdc' >> /etc/modules
#echo '\n# USB Gadget Serial console port\nttyGS0' >> /etc/securetty
#systemctl enable getty@ttyGS0.service
#Setup Ethernet Port
echo 'g_ether' >> /etc/modules
sed -i 's/INTERFACESv4=""/INTERFACESv4="usb0"/g' /etc/default/isc-dhcp-server
systemctl enable isc-dhcp-server
EOF

cd "${basedir}"

# Do the kernel stuff...
git clone --depth 1 -b gateworks_4.20.7 https://github.com/gateworks/linux-imx6 ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Don't change the version because of our patches.
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf- mrproper
patch -p1 < ${current_dir}/patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 < ${current_dir}/patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
# Remove redundant YYLOC global declaration
patch -p1 < ${current_dir}/patches/11647f99b4de6bc460e106e876f72fc7af3e54a6-1.patch
cp ${current_dir}/kernel-configs/gateworks-ventana-4.20.7.config .config
cp ${current_dir}/kernel-configs/gateworks-ventana-4.20.7.config ${work_dir}/usr/src/gateworks-ventana-4.20.7.config
make -j $(grep -c processor /proc/cpuinfo)
make uImage LOADADDR=0x10008000
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/dts/imx6*-gw*.dtb ${work_dir}/boot/
cp arch/arm/boot/uImage ${work_dir}/boot/
# cleanup
cd ${work_dir}/usr/src/kernel
make mrproper

# Pull in imx6 smda/vpu firmware for vpu.
mkdir -p ${work_dir}/lib/firmware/vpu
mkdir -p ${work_dir}/lib/firmware/imx/sdma
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6dl.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6dl.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6d.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6d.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/imx/sdma/sdma-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/imx/sdma/sdma-imx6q.bin

# Not using extlinux.conf just yet...
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot.
#sed -i -e 's/append.*/append root=\/dev\/mmcblk0p1 rootfstype=$fstype video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 console=ttymxc0,115200n8 console=tty1 consoleblank=0 rw rootwait/g' ${work_dir}/boot/extlinux/extlinux.conf

cd ${current_dir}

# Calculate the space to create the image and create.
make_image

# Create the disk partitions it
parted -s ${current_dir}/${imagename}.img mklabel msdos
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype 4MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
rootp="${loopdevice}p1"

# Create file systems
log "Formating partitions" green
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root/
mount "${rootp}" "${basedir}"/root

# We do this here because we don't want to hardcode the UUID for the partition during creation.
# systemd doesn't seem to be generating the fstab properly for some people, so let's create one.
cat <<EOF >"${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
UUID=$(blkid -s UUID -o value ${rootp})  /               $fstype    defaults,noatime  0       1
EOF

log "Rsyncing rootfs into image file" green
rsync -HPavz -q "${work_dir}"/ "${basedir}"/root/
sync

# Umount filesystem
umount -l "${rootp}"

# Check filesystem
e2fsck -y -f "$rootp"

# Remove loop devices
kpartx -dv "${loopdevice}" 
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone wrong.
clean_build