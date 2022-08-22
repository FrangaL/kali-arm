#!/usr/bin/env bash
#
# Kali Linux ARM build-script for CubieBoard2 (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/cubieboard2/
#

# Hardware model
hw_model=${hw_model:-"cubieboard2"}

# Architecture (arm64, armhf, armel)
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

# Calculate the space to create the image and create
make_image

# Load the ethernet module since it doesn't load automatically at boot
echo "sunxi_emac" >>${work_dir}/etc/modules

# Kernel section.  If you want to us ea custom kernel, or configuration, replace
# them in this section
# Get, compile and install kernel
cd ${base_dir}
git clone --depth 1 https://github.com/linux-sunxi/u-boot-sunxi
git clone --depth 1 https://github.com/linux-sunxi/linux-sunxi -b stage/sunxi-3.4 ${work_dir}/usr/src/kernel
git clone --depth 1 https://github.com/linux-sunxi/sunxi-tools
git clone --depth 1 https://github.com/linux-sunxi/sunxi-boards

cd "${base_dir}"/sunxi-tools
make fex2bin
./fex2bin "${base_dir}"/sunxi-boards/sys_config/a20/cubieboard2.fex ${work_dir}/boot/script.bin

cd ${work_dir}/usr/src/kernel
git rev-parse HEAD >${work_dir}/usr/src/kernel-at-commit
patch -p1 --no-backup-if-mismatch <${repo_dir}/patches/mac80211.patch
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
cp ${repo_dir}/kernel-configs/sun7i.config .config
cp ${repo_dir}/kernel-configs/sun7i.config ${work_dir}/usr/src/sun7i.config
make -j $(grep -c processor /proc/cpuinfo) uImage modules
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/uImage ${work_dir}/boot
make mrproper
cp ../sun7i.config .config
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

# Create boot.txt file
cat <<EOF >${work_dir}/boot/boot.cmd
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait panic=10 ${extra} rw rootfstype=$fstype net.ifnames=0
fatload mmc 0 0x43000000 script.bin
fatload mmc 0 0x48000000 uImage
bootm 0x48000000
EOF

# Create u-boot boot script image
mkimage -A arm -T script -C none -d ${work_dir}/boot/boot.cmd ${work_dir}/boot/boot.scr

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

echo "Rsyncing rootfs to image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

cd "${base_dir}"/u-boot-sunxi/

# Build u-boot
make distclean
make Cubieboard2_config
make -j $(nproc)

dd if=u-boot-sunxi-with-spl.bin of=${loopdevice} bs=1024 seek=8

cd "${base_dir}"

# Load default finish_image configs
include finish_image
