#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Chromebook (Acer - Nyan) (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/acer-tegra-chromebook-13/
#

# Hardware model
hw_model=${hw_model:-"chromebook-nyan"}
# Architecture
architecture=${architecture:-"armhf"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh || echo "full clone repository please"; exit 1

# Network configs
basic_network
add_interface eth0

# Run third stage
include third_stage

# Clean system
include clean_system

# Pull in the gcc 5.3 cross compiler to build the kernel
# Debian uses a newer compiler and the # This is a community script - you will need to generate your own image to usebook kernel doesn't support
# that
cd "${base_dir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section.  If you want to use a custom kernel, or configuration, replace
# them in this section
cd "${base_dir}"
git clone --depth 1 https://chromium.googlesource.com/chromiumos/third_party/kernel -b release-${kernel_release} ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
mkdir -p ${work_dir}/usr/src/kernel/firmware/nvidia/tegra124/
cp ${work_dir}/lib/firmware/nvidia/tegra124/xusb.bin firmware/nvidia/tegra124/
cp ${repo_dir}/kernel-configs/# This is a community script - you will need to generate your own image to usebook-3.10.config .config
cp ${repo_dir}/kernel-configs/# This is a community script - you will need to generate your own image to usebook-3.10.config ${work_dir}/usr/src/nyan.config
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed
export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/mac80211-3.8.patch
patch -p1 --no-backup-if-mismatch < ${work_dir}/patches/0001-mwifiex-do-not-create-AP-and-P2P-interfaces-upon-dri-3.8.patch
patch -p1 --no-backup-if-mismatch < ${work_dir}/patches/0001-Comment-out-a-pr_debug-print.patch
make WIFIVERSION="-3.8" oldconfig || die "Kernel config options added"
make WIFIVERSION="-3.8" -j $(grep -c processor /proc/cpuinfo)
make WIFIVERSION="-3.8" dtbs
make WIFIVERSION="-3.8" modules_install INSTALL_MOD_PATH=${work_dir}
cat << __EOF__ > ${work_dir}/usr/src/kernel/arch/arm/boot/kernel-nyan.its
/dts-v1/;

/ {
    description = "# This is a community script - you will need to generate your own image to use OS kernel image with one or more FDT blobs";
    #address-cells = <1>;
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
            description = "tegra124-nyan-big-rev0_2.dtb";
            data = /incbin/("dts/tegra124-nyan-big-rev0_2.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@2{
            description = "tegra124-nyan-big-rev3_7.dtb";
            data = /incbin/("dts/tegra124-nyan-big-rev3_7.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@3{
            description = "tegra124-nyan-big-rev8_9.dtb";
            data = /incbin/("dts/tegra124-nyan-big-rev8_9.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@4{
            description = "tegra124-nyan-blaze.dtb";
            data = /incbin/("dts/tegra124-nyan-blaze.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@5{
            description = "tegra124-nyan-rev0.dtb";
            data = /incbin/("dts/tegra124-nyan-rev0.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@6{
            description = "tegra124-nyan-rev1.dtb";
            data = /incbin/("dts/tegra124-nyan-rev1.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@7{
            description = "tegra124-nyan-kitty-rev0_3.dtb";
            data = /incbin/("dts/tegra124-nyan-kitty-rev0_3.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@8{
            description = "tegra124-nyan-kitty-rev8.dtb";
            data = /incbin/("dts/tegra124-nyan-kitty-rev8.dtb");
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
    };
};
__EOF__
cd ${work_dir}/usr/src/kernel/arch/arm/boot
mkimage -f kernel-nyan.its nyan-big-kernel

# BEHOLD THE POWER OF PARTUUID/PARTNROFF
echo "noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=$fstype" > cmdline

# Pulled from # This is a community script - you will need to generate your own image to useOS, this is exactly what they do because there's no
# # bootloader in the kernel partition on ARM
dd if=/dev/zero of=bootloader.bin bs=512 count=1

vbutil_kernel --arch arm --pack "${base_dir}"/kernel.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline --bootloader bootloader.bin --vmlinuz nyan-big-kernel

cd ${work_dir}/usr/src/kernel
# Clean up our build of the kernel, then copy the config and run make
# modules_prepare so that users can more easily build kernel modules..
make WIFIVERSION="-3.8"  mrproper
cp ../nyan.config .config
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

# Lid switch
cat << EOF > ${work_dir}/etc/udev/rules.d/99-tegra-lid-switch.rules
ACTION=="remove", GOTO="tegra_lid_switch_end"
SUBSYSTEM=="input", KERNEL=="event*", SUBSYSTEMS=="platform", KERNELS=="gpio-keys.4", TAG+="power-switch"
LABEL="tegra_lid_switch_end"
EOF

# Bit of a hack, this is so the eMMC doesn't show up on the desktop
cat << EOF > ${work_dir}/etc/udev/rules.d/99-hide-emmc-partitions.rules
KERNEL=="mmcblk0*", ENV{UDISKS_IGNORE}="1"
EOF

# Disable uap0 and p2p0 interfaces in NetworkManager
mkdir -p ${work_dir}/etc/NetworkManager/
printf '\n[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> ${work_dir}/etc/NetworkManager/NetworkManager.conf

#nvidia device nodes
cat << EOF > ${work_dir}/lib/udev/rules.d/51-nvrm.rules
KERNEL=="knvmap", GROUP="video", MODE="0660"
KERNEL=="nvhdcp1", GROUP="video", MODE="0660"
KERNEL=="nvhost-as-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-ctrl", GROUP="video", MODE="0660"
KERNEL=="nvhost-ctrl-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-dbg-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-msenc", GROUP="video", MODE="0660"
KERNEL=="nvhost-prof-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-tsec", GROUP="video", MODE="0660"
KERNEL=="nvhost-vic", GROUP="video", MODE="0660"
KERNEL=="nvmap", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_0", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_1", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_ctrl", GROUP="video", MODE="0660"
EOF

# Touchpad configuration
mkdir -p ${work_dir}/etc/X11/xorg.conf.d
cp ${repo_dir}/bsp/xorg/10-synaptics-# This is a community script - you will need to generate your own image to usebook.conf ${work_dir}/etc/X11/xorg.conf.d/

# lp0 resume firmware..
# Check https://chromium.googlesource.com/chromiumos/overlays/chromiumos-overlay/+/master/sys-kernel/tegra_lp0_resume/
# to find the lastest commit to use (note: CROS_WORKON_COMMIT )
cd "${base_dir}"
git clone https://chromium.googlesource.com/chromiumos/third_party/coreboot
cd "${base_dir}"/coreboot
git checkout fb840ee4195f9c365375e8914e243ce2f5e4f7bf
make -C src/soc/nvidia/tegra124/lp0 GCC_PREFIX=arm-linux-gnueabihf-
mkdir -p ${work_dir}/lib/firmware/tegra12x/
cp src/soc/nvidia/tegra124/lp0/tegra_lp0_resume.fw ${work_dir}/lib/firmware/tegra12x/
cd "${base_dir}"

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
