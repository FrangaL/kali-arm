#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Utilite Pro (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/utilite-pro/
#

# Hardware model
hw_model=${hw_model:-"utilite-pro"}
# Architecture
architecture=${architecture:-"armhf"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
add_interface eth0

# Run third stage
include third_stage

# Clean system
include clean_system

cat << EOF >> ${work_dir}/etc/udev/links.conf
M   ttymxc3 c   5 1
EOF

cat << EOF >> ${work_dir}/etc/securetty
ttymxc3
EOF


cd ${base_dir}
# Clone a cross compiler to use instead of the Kali one due to kernel age
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
git clone --branch utilite/devel --depth 1 https://github.com/utilite-computer/linux-kernel ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/mac80211.patch
# Needed for issues with hdmi being inited already in u-boot
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/f922b0d.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
# This patch is necessary for older revisions of the Utilite so leave the patch
# and comment in the repo to know why this is here.  Should be fixed by a u-boot
# upgrade but CompuLab haven't released it yet, so leave it here for now
#patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/31727b0.patch
cp ${repo_dir}/kernel-configs/utilite-3.10.config .config
cp ${repo_dir}/kernel-configs/utilite-3.10.config ${work_dir}/usr/src/utilite-3.10.config
touch .scmversion
export ARCH=arm
export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
make -j $(grep -c processor /proc/cpuinfo)
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/zImage ${work_dir}/boot/zImage-cm-fx6
cp arch/arm/boot/dts/imx6q-sbc-fx6m.dtb ${work_dir}/boot/imx6q-sbc-fx6m.dtb
make mrproper
cp ../utilite-3.10.config .config
cd "${base_dir}"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${base_dir}"

# Create a file to set up our u-boot environment
cat << EOF > ${work_dir}/boot/boot.txt
setenv mmcdev 2
setenv bootargs 'earlyprintk console=ttymxc3,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=$fstype rw rootwait net.ifnames=0'
setenv loadaddr  0x10800000
setenv fdtaddr   0x15000000
setenv bootm_low 0x15000000
setenv zimage zImage-cm-fx6
setenv dtb imx6q-sbc-fx6m.dtb
#setenv kernel uImage-cm-fx6

load mmc \${mmcdev}:1 \${loadaddr} \${zimage}
load mmc \${mmcdev}:1 \${fdtaddr} \${dtb}
bootz \${loadaddr} - \${fdtaddr}
#load mmc \${mmcdev}:1 \${loadaddr} \${kernel}
#bootm \${loadaddr}
EOF

# And generate the boot.scr
mkimage -A arm -T script -C none -d ${work_dir}/boot/boot.txt ${work_dir}/boot/boot.scr

cd "${base_dir}"

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
echo "Creating image file ${image_name}.img"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary fat32 1MiB ${bootsize}MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype ${bootsize}MiB 100%

# Set the partition variables
make_loop
# Create file systems
mkfs_partitions
# Make fstab.
make_fstab

# Create the dirs for the partitions and mount them
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root
mkdir -p "${base_dir}"/root/boot
mount ${bootp} "${base_dir}"/root/boot

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

# Load default finish_image configs
include finish_image
