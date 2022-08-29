#!/usr/bin/env bash
#
# Kali Linux ARM build-script for CuBox (32-bit) - Original Marvell based NOT Freescale based
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/cubox/
#

# Hardware model
hw_model=${hw_model:-"cubox"}

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

# We need an older cross compiler due to kernel age
cd "${base_dir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
git clone --depth 1 https://github.com/rabeeh/linux.git ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD >${work_dir}/usr/src/kernel-at-commit
patch -p1 --no-backup-if-mismatch <${repo_dir}/patches/mac80211.patch
patch -p1 --no-backup-if-mismatch <${repo_dir}/patches/remove-defined-from-timeconst.patch
touch .scmversion
export ARCH=arm
export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
make cubox_defconfig
cp .config ${work_dir}/usr/src/cubox.config
make -j $(grep -c processor /proc/cpuinfo) uImage modules
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/uImage ${work_dir}/boot
make mrproper
cp ../cubox.config .config
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
cat <<EOF >${work_dir}/boot/boot.txt
echo "== Executing \${directory}\${bootscript} on \${device_name} partition \${partition} =="

setenv unit_no 0
setenv root_device ?

if itest.s \${device_name} -eq usb; then
    itest.s \$root_device -eq ? && ext3ls usb 0:1 /dev && setenv root_device /dev/sda1 && setenv unit_no 0
    itest.s \$root_device -eq ? && ext3ls usb 1:1 /dev && setenv root_device /dev/sda1 && setenv unit_no 1

fi

if itest.s \${device_name} -eq mmc; then
    itest.s \$root_device -eq ? && ext3ls mmc 0:2 /dev && setenv root_device /dev/mmcblk0p2
    itest.s \$root_device -eq ? && ext3ls mmc 0:1 /dev && setenv root_device /dev/mmcblk0p1

fi

if itest.s \${device_name} -eq ide; then
    itest.s \$root_device -eq ? && ext3ls ide 0:1 /dev && setenv root_device /dev/sda1

fi

if itest.s \$root_device -ne ?; then
    setenv bootargs "console=ttyS0,115200n8 vmalloc=448M video=dovefb:lcd0:1920x1080-32@60-edid clcd.lcd0_enable=1 clcd.lcd1_enable=0 root=\${root_device} rootfstype=$fstype rw net.ifnames=0"
    setenv loadimage "\${fstype}load \${device_name} \${unit_no}:\${partition} 0x00200000 \${directory}\${image_name}"
    \$loadimage && bootm 0x00200000

    echo "!! Unable to load \${directory}\${image_name} from \${device_name} \${unit_no}:\${partition} !!"

    exit

fi

echo "!! Unable to locate root partition on \${device_name} !!"
EOF

# Create u-boot boot script image
mkimage -A arm -T script -C none -d ${work_dir}/boot/boot.txt ${work_dir}/boot/boot.scr

cd "${base_dir}"

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype 1MiB 100%

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

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

# Load default finish_image configs
include finish_image
