#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Beaglebone Black (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/beaglebone-black/
#

# Hardware model
hw_model=${hw_model:-"beaglebone-black"}
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

status_stage3 'Enable ttyO0 in udev links config'
cat << _EOF_ >> /etc/udev/links.conf
M   ttyO0 c 5 1
_EOF_

status_stage3 'Enable root login on serial'
cat << _EOF_ >> /etc/securetty
ttyO0
_EOF_

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyO0 115200 vt100" >> /etc/inittab

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

status 'Kernel compile'
git clone https://github.com/beagleboard/linux -b 4.14 --depth 1 ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed
export CROSS_COMPILE=arm-linux-gnueabihf-
touch .scmversion
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/kali-wifi-injection-4.14.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make bb.org_defconfig
make -j $(grep -c processor /proc/cpuinfo)
cp arch/arm/boot/zImage ${work_dir}/boot/zImage
mkdir -p ${work_dir}/boot/dtbs
cp arch/arm/boot/dts/*.dtb ${work_dir}/boot/dtbs/
make INSTALL_MOD_PATH=${work_dir} modules_install
#make INSTALL_MOD_PATH=${work_dir} firmware_install
make mrproper
make bb.org_defconfig
cd "${base_dir}"

status 'Create uEnv.txt file'
cat << EOF > ${work_dir}/boot/uEnv.txt
#u-boot eMMC specific overrides; Angstrom Distribution (BeagleBone Black) 2013-06-20
kernel_file=zImage
initrd_file=uInitrd

loadzimage=load mmc \${mmcdev}:\${mmcpart} \${loadaddr} \${kernel_file}
loadinitrd=load mmc \${mmcdev}:\${mmcpart} 0x81000000 \${initrd_file}; setenv initrd_size \${filesize}
loadfdt=load mmc \${mmcdev}:\${mmcpart} \${fdtaddr} /dtbs/\${fdtfile}
#

console=ttyO0,115200n8
mmcroot=/dev/mmcblk0p2 rw net.ifnames=0
mmcrootfstype=$fstype rootwait fixrtc

##To disable HDMI/eMMC..
#optargs=capemgr.disable_partno=BB-BONELT-HDMI,BB-BONELT-HDMIN,BB-BONE-EMMC-2G

##3.1MP Camera Cape
#optargs=capemgr.disable_partno=BB-BONE-EMMC-2G

mmcargs=setenv bootargs console=\${console} root=\${mmcroot} rootfstype=\${mmcrootfstype} \${optargs}

#zImage:
uenvcmd=run loadzimage; run loadfdt; run mmcargs; bootz \${loadaddr} - \${fdtaddr}

#zImage + uInitrd: where uInitrd has to be generated on the running system
#boot_fdt=run loadzimage; run loadinitrd; run loadfdt
#uenvcmd=run boot_fdt; run mmcargs; bootz \${loadaddr} 0x81000000:\${initrd_size} \${fdtaddr}
EOF

status "Setting up modules.conf"
# rm the symlink if it exists, and the original files if they exist
rm ${work_dir}/etc/modules
rm ${work_dir}/etc/modules-load.d/modules.conf
cat << EOF > ${work_dir}/etc/modules-load.d/modules.conf
g_ether
EOF

status 'Create xorg config'
mkdir -p ${work_dir}/etc/X11/
cat << EOF > ${work_dir}/etc/X11/xorg.conf
Section "Monitor"
  Identifier    "Builtin Default Monitor"
EndSection

Section "Device"
  Identifier    "Builtin Default fbdev Device 0"
  Driver        "fbdev"
  Option        "SWCursor"  "true"
EndSection

Section "Screen"
  Identifier    "Builtin Default fbdev Screen 0"
  Device        "Builtin Default fbdev Device 0"
  Monitor       "Builtin Default Monitor"
  DefaultDepth  16
  # Comment out the above and uncomment the below if using a
  # bbb-view or bbb-exp
  #DefaultDepth 24
EndSection

Section "ServerLayout"
  Identifier    "Builtin Default Layout"
  Screen        "Builtin Default fbdev Screen 0"
EndSection
EOF

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
status 'Fix kernel symlinks'
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${repo_dir}/"

# Unused currently, but this script is a part of using the usb as an ethernet
# device
status 'Download g-ether script'
wget -c https://raw.github.com/RobertCNelson/tools/master/scripts/beaglebone-black-g-ether-load.sh -O ${work_dir}/root/beaglebone-black-g-ether-load.sh
chmod 0755 ${work_dir}/root/beaglebone-black-g-ether-load.sh

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary fat32 1MiB "${bootsize}"MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary "$fstype" "${bootsize}"MiB 100%

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
mkdir -p "${base_dir}"/root/boot
mount "${bootp}" "${base_dir}"/root/boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q --exclude boot "${work_dir}"/ "${base_dir}"/root/
sync

status "Rsyncing rootfs into image file (/boot)"
rsync -rtx -q "${work_dir}"/boot "${base_dir}"/root
sync

# Load default finish_image configs
include finish_image
