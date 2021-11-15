#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Chromebook (ASUS - Veyron) (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/asus-chromebook-flip/
#

# Hardware model
hw_model=${hw_model:-"chromebook-veyron"}
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

cd ${base_dir}

# Kernel section.  If you want to use a custom kernel, or configuration, replace
# them in this section
# Mainline kernel branch
git clone https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git -b linux-4.19.y ${work_dir}/usr/src/kernel
# ChromeOS kernel branch
#git clone --depth 1 https://chromium.googlesource.com/chromiumos/third_party/kernel.git -b release-${kernel_release} ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Check out 4.19.133 which was known to work..
git checkout 17a87580a8856170d59aab302226811a4ae69149
# Mainline kernel config
cp ${base_dir}/../kernel-configs/veyron-4.19.config .config
# (Currently not working) chromeos-based kernel config
#cp ${base_dir}/../kernel-configs/veyron-4.19-cros.config .config
cp .config ${work_dir}/usr/src/veyron.config
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed
export CROSS_COMPILE=arm-linux-gnueabihf-
# This allows us to patch the kernel without it adding -dirty to the kernel version
touch .scmversion
patch -p1 --no-backup-if-mismatch < ${base_dir}/../patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 --no-backup-if-mismatch < ${base_dir}/../patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make -j$(grep -c processor /proc/cpuinfo)
make dtbs
make modules_install INSTALL_MOD_PATH=${work_dir}
cat << __EOF__ > ${work_dir}/usr/src/kernel/arch/arm/boot/kernel-veyron.its
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
            description = "rk3288-veyron-brain.dtb";
            data = /incbin/("dts/rk3288-veyron-brain.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@2{
            description = "rk3288-veyron-jaq.dtb";
            data = /incbin/("dts/rk3288-veyron-jaq.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@3{
            description = "rk3288-veyron-jerry.dtb";
            data = /incbin/("dts/rk3288-veyron-jerry.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@4{
            description = "rk3288-veyron-mickey.dtb";
            data = /incbin/("dts/rk3288-veyron-mickey.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@5{
            description = "rk3288-veyron-minnie.dtb";
            data = /incbin/("dts/rk3288-veyron-minnie.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@6{
	    description = "rk3288-veyron-pinky.dtb";
	    data = /incbin/("dts/rk3288-veyron-pinky.dtb");
	    type = "flat_dt";
	    arch = "arm";
	    compression = "none";
	    hash@1{
		algo = "sha1";
	    };
	};
        fdt@7{
	    description = "rk3288-veyron-speedy.dtb";
	    data = /incbin/("dts/rk3288-veyron-speedy.dtb");
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
    };
};
__EOF__
cd ${work_dir}/usr/src/kernel/arch/arm/boot
mkimage -D "-I dts -O dtb -p 2048" -f kernel-veyron.its veyron-kernel

# BEHOLD THE MAGIC OF PARTUUID/PARTNROFF
echo 'noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=$fstype' > cmdline

# Pulled from ChromeOS, this is exactly what they do because there's no
# bootloader in the kernel partition on ARM
dd if=/dev/zero of=bootloader.bin bs=512 count=1

vbutil_kernel --arch arm --pack "${base_dir}"/kernel.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline --bootloader bootloader.bin --vmlinuz veyron-kernel
cd ${work_dir}/usr/src/kernel
make mrproper
cp ${base_dir}/../kernel-configs/veyron-4.19.config .config
#cp ${base_dir}/../kernel-configs/veyron-4.19-cros.config .config
cd ${base_dir}

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd ${base_dir}

# Disable uap0 and p2p0 interfaces in NetworkManager
mkdir -p ${work_dir}/etc/NetworkManager/
echo -e '\n[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> ${work_dir}/etc/NetworkManager/NetworkManager.conf

# Create these if they don't exist, to make sure we have proper audio with pulse
mkdir -p ${work_dir}/var/lib/alsa/
cp ${base_dir}/../bsp/audio/veyron/asound.state ${work_dir}/var/lib/alsa/asound.state
cp ${base_dir}/../bsp/audio/veyron/default.pa ${work_dir}/etc/pulse/default.pa

# mali rules so users can access the mali0 driver..
cp ${base_dir}/../bsp/udev/50-mali.rules ${work_dir}/etc/udev/rules.d/50-mali.rules
cp ${base_dir}/../bsp/udev/50-media.rules ${work_dir}/etc/udev/rules.d/50-media.rules
# EHCI is apparently quirky
cp ${base_dir}/../bsp/udev/99-rk3288-ehci-persist.rules ${work_dir}/etc/udev/rules.d/99-rk3288-ehci-persist.rules
# Avoid gpio charger wakeup system
cp ${base_dir}/../bsp/udev/99-rk3288-gpio-charger.rules ${work_dir}/etc/udev/rules.d/99-rk3288-gpio-charger.rules
# Rule used to kick start the bluetooth/wifi chip
cp ${base_dir}/../bsp/udev/80-brcm-sdio-added.rules ${work_dir}/etc/udev/rules.d/80-brcm-sdio-added.rules
# Hide the eMMC partitions from udisks
cp ${base_dir}/../bsp/udev/99-hide-emmc-partitions.rules ${work_dir}/etc/udev/rules.d/99-hide-emmc-partitions.rules

# disable btdsio
mkdir -p ${work_dir}/etc/modprobe.d/
cat << EOF > ${work_dir}/etc/modprobe.d/blacklist-btsdio.conf
blacklist btsdio
EOF

# Touchpad configuration
mkdir -p ${work_dir}/etc/X11/xorg.conf.d
cp ${base_dir}/../bsp/xorg/10-synaptics-chromebook.conf ${work_dir}/etc/X11/xorg.conf.d/

# Copy the broadcom firmware files in
mkdir -p ${work_dir}/lib/firmware/brcm/
cp ${base_dir}/../bsp/firmware/veyron/brcm* ${work_dir}/lib/firmware/brcm/
cp ${base_dir}/../bsp/firmware/veyron/BCM* ${work_dir}/lib/firmware/brcm/
# Copy in the touchpad firmwares - same as above
cp ${base_dir}/../bsp/firmware/veyron/elan* ${work_dir}/lib/firmware/
cp ${base_dir}/../bsp/firmware/veyron/max* ${work_dir}/lib/firmware/
cd ${base_dir}

# We need to kick start the sdio chip to get bluetooth/wifi going
cp ${base_dir}/../bsp/firmware/veyron/brcm_patchram_plus ${work_dir}/usr/sbin/

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

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

dd if=${base_dir}/kernel.bin of=${bootp}

cgpt repair ${loopdevice}

# Load default finish_image configs
include finish_image
