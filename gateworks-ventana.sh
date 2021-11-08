#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Gateworks Ventana (32-bit) - Freescale based
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/gateworks-ventana/
#

# Hardware model
hw_model=${hw_model:-"gateworks-ventana"}
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
status_stage3 'Install dhcp server'
eatmydata apt-get install -y isc-dhcp-server || eatmydata apt-get install -y --fix-broken

status_stage3 'Bootloader'
install -m644 /bsp/bootloader/gateworks-ventana/6x_bootscript-ventana.script /boot/6x_bootscript-ventana.script
mkimage -A arm -T script -C none -d /boot/6x_bootscript-ventana.script /boot/6x_bootscript-ventana

status_stage3 'Enable login over serial (No password)'
echo "T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100" >> /etc/inittab

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

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

cd "${base_dir}"

# Do the kernel stuff
status "Kernel stuff"
git clone --depth 1 -b gateworks_4.20.7 https://github.com/gateworks/linux-imx6 ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Don't change the version because of our patches
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf- mrproper
patch -p1 < ${repo_dir}/patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 < ${repo_dir}/patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
# Remove redundant YYLOC global declaration
patch -p1 < ${repo_dir}/patches/11647f99b4de6bc460e106e876f72fc7af3e54a6-1.patch
cp ${repo_dir}/kernel-configs/gateworks-ventana-4.20.7.config .config
cp ${repo_dir}/kernel-configs/gateworks-ventana-4.20.7.config ${work_dir}/usr/src/gateworks-ventana-4.20.7.config
make -j $(grep -c processor /proc/cpuinfo)
make uImage LOADADDR=0x10008000
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/dts/imx6*-gw*.dtb ${work_dir}/boot/
cp arch/arm/boot/uImage ${work_dir}/boot/
# cleanup
cd ${work_dir}/usr/src/kernel
make mrproper

# Pull in imx6 smda/vpu firmware for vpu
status "vpu"
mkdir -p ${work_dir}/lib/firmware/vpu
mkdir -p ${work_dir}/lib/firmware/imx/sdma
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6dl.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6dl.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6d.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6d.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/imx/sdma/sdma-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/imx/sdma/sdma-imx6q.bin

# Not using extlinux.conf just yet.
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
#sed -i -e 's/append.*/append root=\/dev\/mmcblk0p1 rootfstype=$fstype video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 console=ttymxc0,115200n8 console=tty1 consoleblank=0 rw rootwait/g' ${work_dir}/boot/extlinux/extlinux.conf

cd "${repo_dir}/"

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
# Make fsta.
make_fstab

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/
mount "${rootp}" "${base_dir}"/root

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# Load default finish_image configs
include finish_image
