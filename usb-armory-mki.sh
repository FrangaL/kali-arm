#!/usr/bin/env bash
#
# Kali Linux ARM build-script for USB Armory MKI (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/usb-armory-mkii/
#

# Hardware model
hw_model=${hw_model:-"usbarmory-mki"}
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
status_stage3 'Install dhcp and vnc servers'
eatmydata apt-get install -y isc-dhcp-server tightvncserver || eatmydata apt-get install -y --fix-broken

status_stage3 'Allow users to use NetworkManager over ssh'
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

status_stage3 'Remove /etc/modules*'
rm /etc/modules
rm /etc/modules-load.d/modules.conf

status_stage3 'Add our /etc/modules-load.d/'
cat << __EOF__ > /etc/modules-load.d/modules.conf
ledtrig_heartbeat
ci_hdrc_imx
g_ether
#g_mass_storage
#g_multi
__EOF__

status_stage3 'Add our /etc/modprobe.d/'
cat << __EOF__ > /etc/modprobe.d/usbarmory.conf
options g_ether use_eem=0 dev_addr=1a:55:89:a2:69:41 host_addr=1a:55:89:a2:69:42
# To use either of the following, you should create the file /disk.img via dd
# "dd if=/dev/zero of=/disk.img bs=1M count=2048" would create a 2GB disk.img file
#options g_mass_storage file=disk.img
#options g_multi use_eem=0 dev_addr=1a:55:89:a2:69:41 host_addr=1a:55:89:a2:69:42 file=disk.img
__EOF__

status_stage3 'Add our /etc/network/interfaces.d/usb0'
cat << __EOF__ > /etc/network/interfaces.d/usb0
allow-hotplug usb0
iface usb0 inet static
address 10.0.0.1
netmask 255.255.255.0
gateway 10.0.0.2
__EOF__

status_stage3 'Add our /etc/dhcp/dhcpd.conf'
# Debian reads the config from inside /etc/dhcp
cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.old
cat << __EOF__ > /etc/dhcp/dhcpd.conf
# Sample configuration file for ISC dhcpd for Debian
# Original file /etc/dhcp/dhcpd.conf.old

ddns-update-style none;

default-lease-time 600;
max-lease-time 7200;

log-facility local7;

subnet 10.0.0.0 netmask 255.255.255.0 {
  range 10.0.0.2 10.0.0.2;
  default-lease-time 600;
  max-lease-time 7200;
}
__EOF__

status_stage3 'Only listen on usb0'
sed -i -e 's/INTERFACES.*/INTERFACES="usb0"/g' /etc/default/isc-dhcp-server

status_stage3 'Enable dhcp server'
update-rc.d isc-dhcp-server enable

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
status "Kernel stuff"
git clone -b linux-5.4.y --depth 1 git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-none-eabi-
#patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/ARM-drop-cc-option-fallbacks-for-architecture-select.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/kali-wifi-injection-5.4.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-host.dts -O arch/arm/boot/dts/imx53-usbarmory-host.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-gpio.dts -O arch/arm/boot/dts/imx53-usbarmory-gpio.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-spi.dts -O arch/arm/boot/dts/imx53-usbarmory-spi.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-i2c.dts -O arch/arm/boot/dts/imx53-usbarmory-i2c.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-scc2.dts -O arch/arm/boot/dts/imx53-usbarmory-scc2.dts
cp ${repo_dir}/kernel-configs/usbarmory-5.4.config ${work_dir}/usr/src/kernel/.config
cp ${repo_dir}/kernel-configs/usbarmory-5.4.config ${work_dir}/usr/src/usbarmory-5.4.config
make olddefconfig
make LOADADDR=0x70008000 -j $(grep -c processor /proc/cpuinfo) uImage modules imx53-usbarmory-gpio.dtb imx53-usbarmory-i2c.dtb imx53-usbarmory-spi.dtb imx53-usbarmory.dtb imx53-usbarmory-host.dtb imx53-usbarmory-scc2.dtb
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/zImage ${work_dir}/boot/
cp arch/arm/boot/dts/imx53-usbarmory*.dtb ${work_dir}/boot/
make mrproper
# Since these aren't integrated into the kernel yet, mrproper removes them
cp ${repo_dir}/kernel-configs/usbarmory-5.4.config ${work_dir}/usr/src/kernel/.config
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-host.dts -O arch/arm/boot/dts/imx53-usbarmory-host.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-gpio.dts -O arch/arm/boot/dts/imx53-usbarmory-gpio.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-spi.dts -O arch/arm/boot/dts/imx53-usbarmory-spi.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-i2c.dts -O arch/arm/boot/dts/imx53-usbarmory-i2c.dts
wget $githubraw/f-secure-foundry/usbarmory/master/software/kernel_conf/mark-one/imx53-usbarmory-scc2.dts -O arch/arm/boot/dts/imx53-usbarmory-scc2.dts

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
status "building external modules"
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
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
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary ext2 5MiB 100%

# Set the partition variables
make_loop
# Create file systems
rootfstype="ext2" # Force root partition ext2 filesystem
mkfs_partitions
# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

status "u-Boot"
cd "${base_dir}"
wget ftp://ftp.denx.de/pub/u-boot/u-boot-2021.07.tar.bz2
tar xvf u-boot-2021.07.tar.bz2 && cd u-boot-2021.07
wget $githubraw/f-secure-foundry/usbarmory/master/software/u-boot/0001-Fix-microSD-detection-for-USB-armory-Mk-I.patch
patch -p1 --no-backup-if-mismatch < 0001-Fix-microSD-detection-for-USB-armory-Mk-I.patch
make distclean
make usbarmory_config
make ARCH=arm
dd if=u-boot-dtb.imx of=${loopdevice} bs=512 seek=2 conv=fsync
cd "${repo_dir}/"

# Load default finish_image configs
include finish_image
