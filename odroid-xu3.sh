#!/usr/bin/env bash
#
# Kali Linux ARM build-script for ODROID-XU3 (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/odroid-xu3/
#

# Hardware model
hw_model=${hw_model:-"odroid-xu3"}
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
status_stage3 'Enable ttySAC2 in udev links config'
cat << __EOF__ >> /etc/udev/links.conf
M   ttySAC2 c 5 1
__EOF__

status_stage3 'Enable root login on serial'
cat << _EOF_ >> /etc/securetty
ttySAC0
ttySAC1
ttySAC2
_EOF_

status_stage3 'Serial console settings'
# (Auto login on serial console)
#T1:12345:respawn:/sbin/agetty 115200 ttySAC2 vt100 >> /etc/inittab
# (No auto login)
#T1:12345:respawn:/bin/login -f root ttySAC2 /dev/ttySAC2 2>&1' >> /etc/inittab
# Make sure ttySACX is in root/etc/securetty so root can login on serial console below
echo 'T1:12345:respawn:/bin/login -f root ttySAC2 /dev/ttySAC2 2>&1' >> /etc/inittab

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttySAC2 115200 vt100" >> /etc/inittab

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
git clone --depth 1 -b odroidxu4-4.14.y https://github.com/hardkernel/linux.git ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/kali-wifi-injection-4.14.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
cp ${repo_dir}/kernel-configs/odroid-xu3.config .config
cp ${repo_dir}/kernel-configs/odroid-xu3.config ../odroid-xu3.config
make -j $(grep -c processor /proc/cpuinfo)
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/zImage ${work_dir}/boot
cp arch/arm/boot/dts/exynos5422-odroidxu3.dtb ${work_dir}/boot
cp arch/arm/boot/dts/exynos5422-odroidxu3-lite.dtb ${work_dir}/boot
cp arch/arm/boot/dts/exynos5422-odroidxu4.dtb ${work_dir}/boot
cp arch/arm/boot/dts/exynos5422-odroidxu4-kvm.dtb ${work_dir}/boot
make mrproper
cp ${repo_dir}/kernel-configs/odroid-xu3.config .config
cp ${repo_dir}/kernel-configs/odroid-xu3.config ../odroid-xu3.config
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

status "/boot/boot.ini"
cat << EOF > ${work_dir}/boot/boot.ini
ODROIDXU-UBOOT-CONFIG

# U-Boot Parameters
setenv initrd_high "0xffffffff"
setenv fdt_high "0xffffffff"

# Mac address configuration
setenv macaddr "00:1e:06:61:7a:39"

#------------------------------------------------------------------------------------------------------
# Basic Ubuntu Setup. Don't touch unless you know what you are doing
# --------------------------------
setenv bootrootfs "console=tty1 console=ttySAC2,115200n8 root=/dev/mmcblk0p2 rootwait rootfstype=$fstype net.ifnames=0 rw"

# boot commands
# Uncomment the following if you use an initrd
#setenv bootcmd "fatload mmc 0:1 0x40008000 zImage; fatload mmc 0:1 0x42000000 uInitrd; fatload mmc 0:1 0x44000000 exynos5422-odroidxu3.dtb; bootz 0x40008000 0x42000000 0x44000000"
# Uncomment the following if you do NOT use an initrd
setenv bootcmd "fatload mmc 0:1 0x40008000 zImage; fatload mmc 0:1 0x42000000 uInitrd; fatload mmc 0:1 0x44000000 exynos5422-odroidxu3.dtb; bootz 0x40008000 - 0x44000000"

# --- Screen Configuration for HDMI --- #
# ---------------------------------------
# Uncomment only ONE line! Leave all commented for automatic selection
# Uncomment only the setenv line!
# ---------------------------------------
# ODROID-VU forced resolution
# setenv videoconfig "video=HDMI-A-1:1280x800@60"
# -----------------------------------------------
# 1920x1080 (1080P) with monitor provided EDID information. (1080p-edid)
# setenv videoconfig "video=HDMI-A-1:1920x1080@60"
# -----------------------------------------------
# 1920x1080 (1080P) without monitor data using generic information (1080p-noedid)
# setenv videoconfig "drm_kms_helper.edid_firmware=edid/1920x1080.bin"
# -----------------------------------------------
# 1280x720 (720P) with monitor provided EDID information. (720p-edid)
# setenv videoconfig "video=HDMI-A-1:1280x720@60"
# -----------------------------------------------
# 1280x720 (720P) without monitor data using generic information (720p-noedid)
# setenv videoconfig "drm_kms_helper.edid_firmware=edid/1280x720.bin"
# -----------------------------------------------
# 1024x768 without monitor data using generic information
# setenv videoconfig "drm_kms_helper.edid_firmware=edid/1024x768.bin"

# final boot args
setenv bootargs "\${bootrootfs} \${videoconfig} smsc95xx.macaddr=\${macaddr}"
# drm.debug=0xff
# Boot the board
boot
EOF

cd "${repo_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
echo "Creating image file ${image_name}.img"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary fat32 4MiB ${bootsize}MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype ${bootsize}MiB 100%

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
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

# Write the signed u-boot binary to the image so that it will boot
status "u-Boot"
cd "${base_dir}"
git clone --depth 1 -b odroidxu4-v2017.05 https://github.com/hardkernel/u-boot.git "${base_dir}"/u-boot
cd "${base_dir}"/u-boot
alias python=python3
make odroid-xu4_defconfig
make
cd sd_fuse
sh sd_fusing.sh ${loopdevice}
cd "${repo_dir}/"

# Load default finish_image configs
include finish_image
