#!/usr/bin/env bash
#
# Kali Linux ARM build-script for ODROID-C0/C1/C1+ (32-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/odroid-c/
#

# Hardware model
hw_model=${hw_model:-"odroid-c"}
# Architecture
architecture=${architecture:-"armhf"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load default base_image configs
source ./common.d/base_image.sh

# Network configs
basic_network
add_interface eth0

cat << EOF >>  ${work_dir}/third-stage
# Copy all services
install -m644 /bsp/services/all/*.service /etc/systemd/system/
install -m644 /bsp/services/odroid-c2/*.service /etc/systemd/system/

# Create symlink to enable the service..
ln -sf /etc/systemd/system/amlogic.service /etc/systemd/system/multi-user.target.wants/amlogic.service
EOF

# Run third stage
include third_stage

# Clean system
include clean_system

# Clone an older cross compiler to build the older u-boot/kernel
cd "${base_dir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
git clone --depth 1 https://github.com/hardkernel/linux -b odroidc-3.10.y ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm
# NOTE: 3.8 now works with a 4.8 compiler, 3.4 does not!
export CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/mac80211-backports.patch
patch -p1 --no-backup-if-mismatch < ${repo_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make odroidc_defconfig
cp .config ../odroidc.config
make -j $(grep -c processor /proc/cpuinfo)
make uImage
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/uImage ${work_dir}/boot/
cp arch/arm/boot/dts/meson8b_odroidc.dtb ${work_dir}/boot/
make mrproper
cp ../odroidc.config .config
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

# Create a boot.ini file with possible options if people want to change them
cat << EOF > ${work_dir}/boot/boot.ini
ODROIDC-UBOOT-CONFIG

# Possible screen resolutions
# Uncomment only a single Line! The line with setenv written
# At least one mode must be selected

# setenv m "vga"                # 640x480
# setenv m "480p"               # 720x480
# setenv m "576p"               # 720x576
# setenv m "800x480p60hz"       # 800x480
# setenv m "800x600p60hz"       # 800x600
# setenv m "1024x600p60hz"      # 1024x600
# setenv m "1024x768p60hz"      # 1024x768
# setenv m "1360x768p60hz"      # 1360x768
# setenv m "1440x900p60hz"      # 1440x900
# setenv m "1600x900p60hz"      # 1600x900
# setenv m "1680x1050p60hz"     # 1680x1050
# setenv m "720p"               # 720p 1280x720
# setenv m "800p"               # 1280x800
# setenv m "sxga"               # 1280x1024
# setenv m "1080i50hz"          # 1080I@50Hz
# setenv m "1080p24hz"          # 1080P@24Hz
# setenv m "1080p50hz"          # 1080P@50Hz
setenv m "1080p"                # 1080P@60Hz
# setenv m "1920x1200"          # 1920x1200

# HDMI DVI Mode Configuration
setenv vout_mode "hdmi"
# setenv vout_mode "dvi"
# setenv vout_mode "vga"

# HDMI BPP Mode
setenv m_bpp "32"
# setenv m_bpp "24"
# setenv m_bpp "16"

# HDMI Hotplug Force (HPD)
# 1 = Enables HOTPlug Detection
# 0 = Disables HOTPlug Detection and force the connected status
setenv hpd "0"

# CEC Enable/Disable (Requires Hardware Modification)
# 1 = Enables HDMI CEC
# 0 = Disables HDMI CEC
setenv cec "0"

# PCM5102 I2S Audio DAC
# PCM5102 is an I2S Audio Dac Addon board for ODROID-C1+
# Uncomment the line below to __ENABLE__ support for this Addon board
# setenv enabledac "enabledac"

# UHS Card Configuration
# Uncomment the line below to __DISABLE__ UHS-1 MicroSD support
# This might break boot for some brand models of cards
setenv disableuhs "disableuhs"


# Disable VPU (Video decoding engine, Saves RAM!!!)
# 0 = disabled
# 1 = enabled
setenv vpu "1"

# Disable HDMI Output (Again, saves ram!)
# 0 = disabled
# 1 = enabled
setenv hdmioutput "1"

# Default Console Device Setting
# setenv condev "console=ttyS0,115200n8"        # on serial port
# setenv condev "console=tty0"                    # on display (HDMI)
setenv condev "console=tty0 console=ttyS0,115200n8"   # on both



###########################################

if test "\${hpd}" = "0"; then setenv hdmi_hpd "disablehpd=true"; fi
if test "\${cec}" = "1"; then setenv hdmi_cec "hdmitx=cecf"; fi

# Boot Arguments
setenv bootargs "root=/dev/mmcblk0p2 rootfstype=$fstype quiet rootwait rw \${condev} no_console_suspend vdaccfg=0xa000 logo=osd1,loaded,0x7900000,720p,full dmfc=3 cvbsmode=576cvbs hdmimode=\${m} m_bpp=\${m_bpp} vout=\${vout_mode} \${disableuhs} \${hdmi_hpd} \${hdmi_cec} \${enabledac} net.ifnames=0"

# Booting
fatload mmc 0:1 0x21000000 uImage
fatload mmc 0:1 0x22000000 uInitrd
fatload mmc 0:1 0x21800000 meson8b_odroidc.dtb
fdt addr 21800000

if test "\${vpu}" = "0"; then fdt rm /mesonstream; fdt rm /vdec; fdt rm /ppmgr; fi

if test "\${hdmioutput}" = "0"; then fdt rm /mesonfb; fi

# If you're going to use an initrd, uncomment this line and comment out the bottom line
#bootm 0x21000000 0x22000000 0x21800000"
bootm 0x21000000 - 0x21800000"
EOF

cat << EOF > ${work_dir}/usr/bin/amlogic.sh
#!/bin/sh

for x in \$(cat /proc/cmdline); do
    case \${x} in
        m_bpp=*) export bpp=\${x#*=} ;;
        hdmimode=*) export mode=\${x#*=} ;;
    esac
done

HPD_STATE=/sys/class/amhdmitx/amhdmitx0/hpd_state
DISP_CAP=/sys/class/amhdmitx/amhdmitx0/disp_cap
DISP_MODE=/sys/class/display/mode

hdmi=\`cat \$HPD_STATE\`
if [ \$hdmi -eq 1 ]; then
    echo \$mode > \$DISP_MODE
fi

outputmode=\$mode

common_display_setup() {
    fbset -fb /dev/fb1 -g 32 32 32 32 32
    echo \$outputmode > /sys/class/display/mode
    echo 0 > /sys/class/ppmgr/ppscaler
    echo 0 > /sys/class/graphics/fb0/free_scale
    echo 1 > /sys/class/graphics/fb0/freescale_mode

    case \$outputmode in
            800x480*) M="0 0 799 479" ;;
            vga*)  M="0 0 639 749" ;;
            800x600p60*) M="0 0 799 599" ;;
            1024x600p60h*) M="0 0 1023 599" ;;
            1024x768p60h*) M="0 0 1023 767" ;;
            sxga*) M="0 0 1279 1023" ;;
            1440x900p60*) M="0 0 1439 899" ;;
            480*) M="0 0 719 479" ;;
            576*) M="0 0 719 575" ;;
            720*) M="0 0 1279 719" ;;
            800*) M="0 0 1279 799" ;;
            1080*) M="0 0 1919 1079" ;;
            1920x1200*) M="0 0 1919 1199" ;;
            1680x1050p60*) M="0 0 1679 1049" ;;
        1360x768p60*) M="0 0 1359 767" ;;
        1366x768p60*) M="0 0 1365 767" ;;
        1600x900p60*) M="0 0 1599 899" ;;
    esac

    echo \$M > /sys/class/graphics/fb0/free_scale_axis
    echo \$M > /sys/class/graphics/fb0/window_axis
    echo 0x10001 > /sys/class/graphics/fb0/free_scale
    echo 0 > /sys/class/graphics/fb1/free_scale
}

case \$mode in
    800x480*)           fbset -fb /dev/fb0 -g 800 480 800 960 \$bpp;     common_display_setup ;;
    vga*)               fbset -fb /dev/fb0 -g 640 480 640 960 \$bpp;     common_display_setup ;;
    480*)               fbset -fb /dev/fb0 -g 720 480 720 960 \$bpp;     common_display_setup ;;
    800x600p60*)        fbset -fb /dev/fb0 -g 800 600 800 1200 \$bpp;    common_display_setup ;;
    576*)               fbset -fb /dev/fb0 -g 720 576 720 1152 \$bpp;    common_display_setup ;;
    1024x600p60h*)      fbset -fb /dev/fb0 -g 1024 600 1024 1200 \$bpp;  common_display_setup ;;
    1024x768p60h*)      fbset -fb /dev/fb0 -g 1024 768 1024 1536 \$bpp;  common_display_setup ;;
    720*)               fbset -fb /dev/fb0 -g 1280 720 1280 1440 \$bpp;  common_display_setup ;;
    800*)               fbset -fb /dev/fb0 -g 1280 800 1280 1600 \$bpp;  common_display_setup ;;
    sxga*)              fbset -fb /dev/fb0 -g 1280 1024 1280 2048 \$bpp; common_display_setup ;;
    1440x900p60*)       fbset -fb /dev/fb0 -g 1440 900 1440 1800 \$bpp;  common_display_setup ;;
    1080*)              fbset -fb /dev/fb0 -g 1920 1080 1920 2160 \$bpp; common_display_setup ;;
    1920x1200*)         fbset -fb /dev/fb0 -g 1920 1200 1920 2400 \$bpp; common_display_setup ;;
    1360x768p60*)       fbset -fb /dev/fb0 -g 1360 768 1360 1536 \$bpp;  common_display_setup ;;
    1366x768p60*)       fbset -fb /dev/fb0 -g 1366 768 1366 1536 \$bpp;  common_display_setup ;;
    1600x900p60*)       fbset -fb /dev/fb0 -g 1600 900 1600 1800 \$bpp;  common_display_setup ;;
    1680x1050p60*)      fbset -fb /dev/fb0 -g 1680 1050 1680 2100 \$bpp; common_display_setup ;;
esac


# Console unblack
echo 0 > /sys/class/graphics/fb0/blank
echo 0 > /sys/class/graphics/fb1/blank


# Network Tweaks. Thanks to mlinuxguy
echo 32768 > /proc/sys/net/core/rps_sock_flow_entries
echo 2048 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
echo 7 > /sys/class/net/eth0/queues/rx-0/rps_cpus
echo 7 > /sys/class/net/eth0/queues/tx-0/xps_cpus

# Move IRQ's of ethernet to CPU1/2
echo 1,2 > /proc/irq/40/smp_affinity_list
EOF
chmod 0755 ${work_dir}/usr/bin/amlogic.sh

cat << EOF > ${work_dir}/etc/sysctl.d/99-c1-network.conf
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 514400
net.core.wmem_default = 514400
net.ipv4.tcp_rmem = 10240 87380 26214400
net.ipv4.tcp_wmem = 10240 87380 26214400
net.ipv4.udp_rmem_min = 131072
net.ipv4.udp_wmem_min = 131072
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.core.optmem_max = 65535
net.core.netdev_max_backlog = 5000
EOF

cd ${repo_dir}

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
mkdir -p "${base_dir}"/root
mount ${rootp} "${base_dir}"/root
mkdir -p "${base_dir}"/root/boot
mount ${bootp} "${base_dir}"/root/boot

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${base_dir}/root/

# Unmount partitions
sync
umount ${bootp}
umount ${rootp}
kpartx -dv ${loopdevice}

cd ${base_dir}
# Build the latest u-boot bootloader, and then use the Hardkernel script to fuse
# it to the image.  This is required because of a requirement that the
# bootloader be signed
git clone --depth 1 https://github.com/hardkernel/u-boot -b odroidc-v2011.03
cd ${base_dir}/u-boot
# https://code.google.com/p/chromium/issues/detail?id=213120
sed -i -e "s/soft-float/float-abi=hard -mfpu=vfpv3/g" \
    arch/arm/cpu/armv7/config.mk
make CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- odroidc_config
make CROSS_COMPILE="${base_dir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- -j $(grep -c processor /proc/cpuinfo)

cd sd_fuse
sh sd_fusing.sh ${loopdevice}

cd "${base_dir}"

# Load default finish_image configs
include finish_image
