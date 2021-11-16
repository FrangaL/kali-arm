#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Chromebook (Samsung - Exynos) (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/samsung-chromebook/
#

# Hardware model
hw_model=${hw_model:-"chromebook-exynos"}
# Architecture
architecture=${architecture:-"armhf"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
#add_interface eth0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
# Install samsung firmware
eatmydata apt-get install -y firmware-samsung
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

kernel_release="R71-11151.B-chromeos-3.8"

# Pull in the gcc 4.7 cross compiler to build the kernel
# Debian uses a gcc that the chromebook kernel doesn't have support for
cd "${base_dir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section.  If you want to use a custom kernel, or configuration, replace
# them in this section
git clone --depth 1 https://chromium.googlesource.com/chromiumos/third_party/kernel -b release-${kernel_release} ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
cp ${repo_dir}/kernel-configs/chromebook-3.8.config .config
cp ${repo_dir}/kernel-configs/chromebook-3.8.config ../exynos.config
cp ${repo_dir}/kernel-configs/chromebook-3.8_wireless-3.4.config exynos_wifi34.config
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed
export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/mac80211.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-exynos-drm-smem-start-len.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-mwifiex-do-not-create-AP-and-P2P-interfaces-upon-dri.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-Commented-out-pr_debug-line.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0002-Fix-udl_connector-include.patch
make oldconfig || die "Kernel config options added"
make -j $(grep -c processor /proc/cpuinfo)
make dtbs
make modules_install INSTALL_MOD_PATH=${work_dir}
cat << __EOF__ > ${work_dir}/usr/src/kernel/arch/arm/boot/kernel-exynos.its
/dts-v1/;

/ {
    description = "Chrome OS kernel image with one or more FDT blobs";
    images {
        kernel@1{
            description = "kernel";
            data = /incbin/("zImage");
            type = "kernel_noload";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0>;
            entry = <0>;
        };
        fdt@1{
            description = "exynos5250-skate.dtb";
            data = /incbin/("dts/exynos5250-skate.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@2{
            description = "exynos5250-smdk5250.dtb";
            data = /incbin/("dts/exynos5250-smdk5250.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@3{
            description = "exynos5250-snow-rev4.dtb";
            data = /incbin/("dts/exynos5250-snow-rev4.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@4{
            description = "exynos5250-snow-rev5.dtb";
            data = /incbin/("dts/exynos5250-snow-rev5.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@5{
            description = "exynos5250-spring.dtb";
            data = /incbin/("dts/exynos5250-spring.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@6{
            description = "exynos5420-peach-kirby.dtb";
            data = /incbin/("dts/exynos5420-peach-kirby.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@7{
            description = "exynos5420-peach-pit-rev3_5.dtb";
            data = /incbin/("dts/exynos5420-peach-pit-rev3_5.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@8{
            description = "exynos5420-peach-pit-rev4.dtb";
            data = /incbin/("dts/exynos5420-peach-pit-rev4.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@9{
            description = "exynos5420-peach-pit.dtb";
            data = /incbin/("dts/exynos5420-peach-pit.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@10{
            description = "exynos5420-smdk5420.dtb";
            data = /incbin/("dts/exynos5420-smdk5420.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@11{
            description = "exynos5420-smdk5420-evt0.dtb";
            data = /incbin/("dts/exynos5420-smdk5420-evt0.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@12{
            description = "exynos5422-peach-pi.dtb";
            data = /incbin/("dts/exynos5422-peach-pi.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@13{
            description = "exynos5440-ssdk5440.dtb";
            data = /incbin/("dts/exynos5440-ssdk5440.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
    };
    configurations {
        default = "conf@1";
        conf@1{
            kernel = "kernel@1";
            fdt = "fdt@1";
        };
        conf@2{
            kernel = "kernel@1";
            fdt = "fdt@2";
        };
        conf@3{
            kernel = "kernel@1";
            fdt = "fdt@3";
        };
        conf@4{
            kernel = "kernel@1";
            fdt = "fdt@4";
        };
        conf@5{
            kernel = "kernel@1";
            fdt = "fdt@5";
        };
        conf@6{
            kernel = "kernel@1";
            fdt = "fdt@6";
        };
        conf@7{
            kernel = "kernel@1";
            fdt = "fdt@7";
        };
        conf@8{
            kernel = "kernel@1";
            fdt = "fdt@8";
        };
        conf@9{
            kernel = "kernel@1";
            fdt = "fdt@9";
        };
        conf@10{
            kernel = "kernel@1";
            fdt = "fdt@10";
        };
        conf@11{
            kernel = "kernel@1";
            fdt = "fdt@11";
        };
        conf@12{
            kernel = "kernel@1";
            fdt = "fdt@12";
        };
        conf@13{
            kernel = "kernel@1";
            fdt = "fdt@13";
        };
    };
};
__EOF__
cd ${work_dir}/usr/src/kernel/arch/arm/boot
mkimage -D "-I dts -O dtb -p 2048" -f kernel-exynos.its exynos-kernel

# microSD Card
echo 'noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=$fstype' > cmdline

# Pulled from ChromeOS, this is exactly what they do because there's no
# bootloader in the kernel partition on ARM
dd if=/dev/zero of=bootloader.bin bs=512 count=1

vbutil_kernel --arch arm --pack "${base_dir}"/kernel.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline --bootloader bootloader.bin --vmlinuz exynos-kernel

cd ${work_dir}/usr/src/kernel/
make mrproper
cp ../exynos.config .config
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
cd ${repo_dir}

# Bit of a hack to hide eMMC partitions from XFCE
cat << EOF > ${work_dir}/etc/udev/rules.d/99-hide-emmc-partitions.rules
KERNEL=="mmcblk0*", ENV{UDISKS_IGNORE}="1"
EOF

# Disable uap0 and p2p0 interfaces in NetworkManager
mkdir -p ${work_dir}/etc/NetworkManager/
printf '\n[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> ${work_dir}/etc/NetworkManager/NetworkManager.conf

# Touchpad configuration
mkdir -p ${work_dir}/etc/X11/xorg.conf.d
cp ${repo_dir}/bsp/xorg/10-synaptics-chromebook.conf ${work_dir}/etc/X11/xorg.conf.d/

# Turn off Accel
cat << EOF > ${work_dir}/etc/X11/xorg.conf.d/20-modesetting.conf
Section "Device"
    Identifier  "Exynos Video"
    Driver      "modesetting"
    Option      "AccelMethod"   "none"
EndSection
EOF

# Mali GPU rules aka mali-rules package in ChromeOS
cat << EOF > ${work_dir}/etc/udev/rules.d/50-mali.rules
KERNEL=="mali0", MODE="0660", GROUP="video"
EOF

# Video rules aka media-rules package in ChromeOS
cat << EOF > ${work_dir}/etc/udev/rules.d/50-media.rules
ATTR{name}=="s5p-mfc-dec", SYMLINK+="video-dec"
ATTR{name}=="s5p-mfc-enc", SYMLINK+="video-enc"
ATTR{name}=="s5p-jpeg-dec", SYMLINK+="jpeg-dec"
ATTR{name}=="exynos-gsc.0*", SYMLINK+="image-proc0"
ATTR{name}=="exynos-gsc.1*", SYMLINK+="image-proc1"
ATTR{name}=="exynos-gsc.2*", SYMLINK+="image-proc2"
ATTR{name}=="exynos-gsc.3*", SYMLINK+="image-proc3"
ATTR{name}=="rk3288-vpu-dec", SYMLINK+="video-dec"
ATTR{name}=="rk3288-vpu-enc", SYMLINK+="video-enc"
ATTR{name}=="go2001-dec", SYMLINK+="video-dec"
ATTR{name}=="go2001-enc", SYMLINK+="video-enc"
ATTR{name}=="mt81xx-vcodec-dec", SYMLINK+="video-dec"
ATTR{name}=="mt81xx-vcodec-enc", SYMLINK+="video-enc"
ATTR{name}=="mt81xx-image-proc", SYMLINK+="image-proc0"
EOF

# This is for Peach - kinda a hack, never really worked properly they say
# Ambient light sensor
cat << EOF > ${work_dir}/lib/udev/light-sensor-set-multiplier.sh
#!/bin/sh

# Copyright (c) 2012 The Chromium OS Authors. All rights reserved
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file

# In iio/devices, find device0 on 3.0.x kernels and iio:device0 on 3.2 kernels
for FILE in /sys/bus/iio/devices/*/in_illuminance0_calibscale; do
  # Set the light sensor calibration value
  echo 5.102040 > \$FILE && break;
done

for FILE in /sys/bus/iio/devices/*/in_illuminance1_calibscale; do
  # Set the IR compensation calibration value
  echo 0.053425 > \$FILE && break;
done

for FILE in /sys/bus/iio/devices/*/range; do
  # Set the light sensor range value (max lux)
  echo 16000 > \$FILE && break;
done

for FILE in /sys/bus/iio/devices/*/continuous; do
  # Change the measurement mode to the continuous mode
  echo als > \$FILE && break;
done
EOF

cat << EOF > ${work_dir}/etc/udev/rules.d/99-light-sensor.rules
# Calibrate the light sensor when the isl29018 driver is installed
ACTION=="add", SUBSYSTEM=="drivers", KERNEL=="isl29018", RUN+="light-sensor-set-multiplier.sh"
EOF

cd ${repo_dir}

# Calculate the space to create the image and create
make_image

# Create the disk and partition it
echo "Creating image file ${image_name}.img"
parted -s "${image_dir}/${image_name}.img" mklabel gpt
cgpt create -z "${image_dir}/${image_name}.img"
cgpt create "${image_dir}/${image_name}.img"

cgpt add -i 1 -t kernel -b 8192 -s 32768 -l kernel -S 1 -T 5 -P 10 "${image_dir}/${image_name}.img"
cgpt add -i 2 -t data -b 40960 -s `expr $(cgpt show "${image_dir}/${image_name}.img" | grep 'Sec GPT table' | awk '{ print \$1 }')  - 40960` -l Root "${image_dir}/${image_name}.img"

# Set the partition variables
make_loop
# Create file systems
mkfs_partitions
# Make fstab.
make_fstab

mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

dd if="${base_dir}"/kernel.bin of=${bootp}

cgpt repair ${loopdevice}

# Load default finish_image configs
include finish_image
