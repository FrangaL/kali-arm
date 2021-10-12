#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Gateworks Newport (64-bit) - Cavium Octeon
# https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/gateworks-newport/
#

# Hardware model
hw_model=${hw_model:-"gateworks-newport"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
include network
add_interface eth0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'We replace the u-boot menu defaults here so we can make sure the build system does not poison it'
# We use _EOF_ so that the third-stage script doesn't end prematurely
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttymxc1,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=$fstype net.ifnames=0"
_EOF_

status_stage3 'Enable login over serial (No password)'
echo "T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100" >> /etc/inittab
EOF

# Run third stage
include third_stage

# Clean system
include clean_system
trap clean_build ERR SIGTERM SIGINT

cd "${base_dir}/"

# Do the kernel stuff
status "Kernel stuff"
git clone --depth 1 -b v5.4.45-newport https://github.com/gateworks/linux-newport ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Don't change the version because of our patches
touch .scmversion
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
patch -p1 < ${current_dir}/patches/kali-wifi-injection-5.4.patch
patch -p1 < ${current_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
cp ${current_dir}/kernel-configs/gateworks-newport-5.4.45.config .config
cp ${current_dir}/kernel-configs/gateworks-newport-5.4.45.config ${work_dir}/usr/src/gateworks-newport-5.4.45.config
#build
make -j $(grep -c processor /proc/cpuinfo)
# install compressed kernel in a kernel.itb
mkimage -f auto -A arm64 -O linux -T kernel -C gzip -n "Newport Kali Kernel" -a 20080000 -e 20080000 -d arch/arm64/boot/Image.gz kernel.itb
cp kernel.itb ${work_dir}/boot
# install kernel modules
make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${work_dir} modules_install
make INSTALL_HDR_PATH=${work_dir}/usr headers_install
# cryptodev-linux build/install
git clone --depth 1 https://github.com/cryptodev-linux/cryptodev-linux ${work_dir}/usr/src/cryptodev-linux
cd ${work_dir}/usr/src
make -C cryptodev-linux KERNEL_DIR=${work_dir}/usr/src/kernel
make -C cryptodev-linux KERNEL_DIR=${work_dir}/usr/src/kernel DESTDIR=${work_dir} INSTALL_MOD_PATH=${work_dir} install
# wireguard-linux-compat build/install
git clone --depth 1 https://git.zx2c4.com/wireguard-linux-compat ${work_dir}/usr/src/wireguard-linux-compat
make -C ${work_dir}/usr/src/kernel M=../wireguard-linux-compat/src modules
make -C ${work_dir}/usr/src/kernel M=../wireguard-linux-compat/src INSTALL_MOD_PATH=${work_dir} modules_install
# cleanup
cd ${work_dir}/usr/src/kernel
make mrproper

# U-boot script
status "U-boot script"
install -m644 ${current_dir}/bsp/bootloader/gateworks-newport/newport.scr ${work_dir}/boot/newport.script
mkimage -A arm64 -T script -C none -d ${work_dir}/boot/newport.script ${work_dir}/boot/newport.scr
rm ${work_dir}/boot/newport.script

# reboot script
status "Reboot script"
cat << EOF > ${work_dir}/lib/systemd/system-shutdown/gsc-poweroff
#!/usr/bin/env bash
# use GSC to power cycle the system
echo 2 > /sys/bus/i2c/devices/0-0020/powerdown
done
EOF
chmod +x ${work_dir}/lib/systemd/system-shutdown/gsc-poweroff

# Calculate the space to create the image
root_size=$(du -s -B1 ${work_dir} --exclude=${work_dir}/boot | cut -f1)
root_extra=$((${root_size}/1024/1000*5*1024/5))
raw_size=$(($((${free_space}*1024))+${root_extra}))

# Weird Boot Partition
status "Creating image file ${image_name}.img"
mkdir -p "${image_dir}"
wget http://dev.gateworks.com/newport/boot_firmware/firmware-newport.img -O "${image_dir}/${image_name}.img"
fallocate -l $(echo ${raw_size}Ki | numfmt --from=iec-i --to=si) "${base_dir}/${image_name}.img"
dd if=${base_dir}/${image_name}.img of="${image_dir}/${image_name}.img" bs=16M seek=1
echo ", +" | sfdisk -N 2 "${image_dir}/${image_name}.img"

# Set the partition variables
loopdevice=$(losetup -f --show "${image_dir}/${image_name}.img")
device=$(kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1)
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p2

# Create file systems
if [[ $fstype == ext4 ]]; then
  features="^64bit,^metadata_csum"
elif [[ $fstype == ext3 ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

# Create an fstab so that we don't mount / read-only
status "/etc/fstab"
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

status "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/
sync

# Load default finish_image configs
include finish_image
