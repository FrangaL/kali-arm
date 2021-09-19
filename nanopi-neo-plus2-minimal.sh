#!/bin/bash -e
# This is the NanoPi NEO PLUS2 minimal Kali ARM 64 bit build script - http://www.kali.org/get-kali
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"nanopi-neo-plus2-minimal"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"none"}

# Load common variables
include variables
# Checks script enviroment
include check
# Packages build list
include packages
# Execute initial debootstrap
debootstrap_exec http://http.kali.org/kali
# Enable eatmydata in compilation
include eatmydata
# debootstrap second stage
systemd-nspawn_exec eatmydata /debootstrap/debootstrap --second-stage
# Define sources.list
include sources.list
# APT options
include apt_options
# So X doesn't complain, we add kali to hosts
include hosts
# Set hostname
set_hostname "${hostname}"
# Network configs
include network
add_interface eth0
# Copy directory bsp into build dir.
cp -rp bsp "${work_dir}"

# Eventually this should become a systemd service, but for now, we use the same
# init.d file that they provide and we let systemd handle the conversion.
mkdir -p ${work_dir}/etc/init.d/
cat << 'EOF' > ${work_dir}/etc/init.d/brcm_patchram_plus
#!/bin/bash

### BEGIN INIT INFO
# Provides:             brcm_patchram_plus
# Required-Start:       $remote_fs $syslog
# Required-Stop:        $remote_fs $syslog
# Default-Start:        2 3 4 5
# Default-Stop:
# Short-Description:    brcm_patchram_plus
### END INIT INFO

function reset_bt()
{
    BTWAKE=/proc/bluetooth/sleep/btwake
    if [ -f ${BTWAKE} ]; then
        echo 0 > ${BTWAKE}
    fi
    index=`rfkill list | grep $1 | cut -f 1 -d":"`
    if [[ -n ${index} ]]; then
        rfkill block ${index}
        sleep 1
        rfkill unblock ${index}
        sleep 1
    fi
}

case "$1" in
    start|"")
        index=`rfkill list | grep "sunxi-bt" | cut -f 1 -d":"`
        brcm_try_log=/var/log/brcm/brcm_try.log
        brcm_log=/var/log/brcm/brcm.log
        brcm_err_log=/var/log/brcm/brcm_err.log
        if [ -d /sys/class/rfkill/rfkill${index} ]; then
            rm -rf ${brcm_log}
            reset_bt "sunxi-bt"
            [ -d /var/log/brcm ] || mkdir -p /var/log/brcm
            chmod 0660 /sys/class/rfkill/rfkill${index}/state
            chmod 0660 /sys/class/rfkill/rfkill${index}/type
            chgrp dialout /sys/class/rfkill/rfkill${index}/state
            chgrp dialout /sys/class/rfkill/rfkill${index}/type
            MACADDRESS=`md5sum /sys/class/sunxi_info/sys_info | cut -b 1-12 | sed -r ':1;s/(.*[^:])([^:]{2})/\1:\2/;t1'`
            let TIMEOUT=150
            while [ ${TIMEOUT} -gt 0 ]; do
                killall -9 /bin/brcm_patchram_plus
                /bin/brcm_patchram_plus -d --patchram /lib/firmware/ap6212/ --enable_hci --bd_addr ${MACADDRESS} --no2bytes --tosleep 5000 /dev/ttyS3 >${brcm_log} 2>&1 &
                sleep 30
                TIMEOUT=$((TIMEOUT-30))
                cur_time=`date "+%H-%M-%S"`
                if grep "Done setting line discpline" ${brcm_log}; then
                    echo "${cur_time}: bt firmware download ok(${TIMEOUT})" >> ${brcm_try_log}
                    if ! grep "fail" ${brcm_try_log}; then
                        reset_bt "hci0"
                        hciconfig hci0 up
                        hciconfig >> ${brcm_try_log}
                        #reboot
                    fi
                    break
                else
                    echo "${cur_time}: bt firmware download fail(${TIMEOUT})" >> ${brcm_try_log}
                    cp ${brcm_log} ${brcm_err_log}
                    reset_bt "sunxi-bt"
                fi
            done
        fi
        ;;

    stop)
    kill `ps --no-headers -C brcm_patchram_plus -o pid`
        ;;
    *)
        echo "Usage: brcm_patchram_plus start|stop" >&2
        exit 3
        ;;
esac
EOF
chmod 755 ${work_dir}/etc/init.d/brcm_patchram_plus

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${minimal_pkgs} || eatmydata apt-get install -y --fix-broken

eatmydata apt-get -y --purge autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/


# Copy script rpi-resizerootfs
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

# Enable rpi-resizerootfs first boot
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# There's no graphical output on this device so
systemctl set-default multi-user

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda || true

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

# Enable runonce
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

# Clean up dpkg.eatmydata
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 755 "${work_dir}"/third-stage
systemd-nspawn_exec /third-stage

# Clean system
include clean_system

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section.
git clone --depth 1 https://github.com/friendlyarm/linux -b sunxi-4.x.y ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
cp ${current_dir}/kernel-configs/neoplus2.config ${work_dir}/usr/src/kernel/.config
cp ${current_dir}/kernel-configs/neoplus2.config ${work_dir}/usr/src/
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/kali-wifi-injection-4.14.patch
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
# Remove the duplicate yylloc define
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/11647f99b4de6bc460e106e876f72fc7af3e54a6.patch
# Use the kernel socket.h instead of host so that we can build on systems with newer headers
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/selinux-use-kernel-socket-definitions.patch
make -j $(grep -c processor /proc/cpuinfo)
make modules
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm64/boot/Image ${work_dir}/boot
cp arch/arm64/boot/dts/allwinner/*.dtb ${work_dir}/boot/
mkdir -p ${work_dir}/boot/overlays/
cp arch/arm64/boot/dts/allwinner/overlays/*.dtb ${work_dir}/boot/overlays/
make mrproper
cd ${current_dir}

# Copy over the firmware for the ap6212 wifi.
# On the neo plus2 default install there are other firmware files installed for
# p2p and apsta but I can't find them publicly posted to friendlyarm's github.
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon.
mkdir -p ${work_dir}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${work_dir}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/config.txt

# The way the base system comes, the firmware seems to be a symlink into the
# ap6212 directory so let's do the same here.
# NOTE: This means we can't install firmware-brcm80211 firmware package because
# the firmware will conflict, and based on testing the firmware in the package
# *will not* work with this device.
mkdir -p ${work_dir}/lib/firmware/brcm
cd ${work_dir}/lib/firmware/brcm
ln -s /lib/firmware/ap6212/fw_bcm43438a1.bin brcmfmac43430a1-sdio.bin
ln -s /lib/firmware/ap6212/nvram_ap6212.txt brcmfmac43430a1-sdio.txt
ln -s /lib/firmware/ap6212/fw_bcm43438a0.bin brcmfmac43430-sdio.bin
ln -s /lib/firmware/ap6212/nvram.txt brcmfmac43430-sdio.txt
cd ${current_dir}

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd ${current_dir}

cat << EOF > ${work_dir}/boot/boot.cmd
# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr

setenv fsck.repair yes
setenv ramdisk rootfs.cpio.gz
setenv kernel Image

setenv env_addr 0x45000000
setenv kernel_addr 0x46000000
setenv ramdisk_addr 0x47000000
setenv dtb_addr 0x48000000
setenv fdtovaddr 0x49000000

fatload mmc 0 \${kernel_addr} \${kernel}
fatload mmc 0 \${ramdisk_addr} \${ramdisk}
if test \$board = nanopi-neo2-v1.1; then
    fatload mmc 0 \${dtb_addr} sun50i-h5-nanopi-neo2.dtb
else
    fatload mmc 0 \${dtb_addr} sun50i-h5-\${board}.dtb
fi
fdt addr \${dtb_addr}

# setup NEO2-V1.1 with gpio-dvfs overlay
if test \$board = nanopi-neo2-v1.1; then
        fatload mmc 0 \${fdtovaddr} overlays/sun50i-h5-gpio-dvfs-overlay.dtb
        fdt resize 8192
    fdt apply \${fdtovaddr}
fi

# setup MAC address
fdt set ethernet0 local-mac-address \${mac_node}

# setup boot_device
fdt set mmc\${boot_mmc} boot_device <1>

setenv fbcon map:0
setenv bootargs console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootfstype=$fstype rw rootwait fsck.repair=\${fsck.repair} panic=10 \${extra} fbcon=\${fbcon} ipv6.disable=1
#booti \${kernel_addr} \${ramdisk_addr}:500000 \${dtb_addr}
booti \${kernel_addr} - \${dtb_addr}
EOF
mkimage -C none -A arm -T script -d ${work_dir}/boot/boot.cmd ${work_dir}/boot/boot.scr

cd ${current_dir}

# Calculate the space to create the image and create.
make_image

# Create the disk partitions it
parted -s ${current_dir}/${imagename}.img mklabel msdos
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype 32MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
rootp="${loopdevice}p1"

# Create file systems
log "Formating partitions" green
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root/
mount "${rootp}" "${basedir}"/root

# We do this here because we don't want to hardcode the UUID for the partition during creation.
# systemd doesn't seem to be generating the fstab properly for some people, so let's create one.
cat <<EOF >"${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
UUID=$(blkid -s UUID -o value ${rootp})  /               $fstype    defaults,noatime  0       1
EOF

log "Rsyncing rootfs into image file" green
rsync -HPavz -q "${work_dir}"/ "${basedir}"/root/
sync

cd "${basedir}"
git clone https://github.com/friendlyarm/u-boot.git
cd u-boot
git checkout sunxi-v2017.x
make nanopi_h5_defconfig
make
dd if=spl/sunxi-spl.bin of=${loopdevice} bs=1024 seek=8
dd if=u-boot.itb of=${loopdevice} bs=1024 seek=40
sync

cd ${current_dir}

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk.
blockdev --flushbufs "${loopdevice}"
python -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Umount filesystem
umount -l "${rootp}"

# Check filesystem
e2fsck -y -f "$rootp"

# Remove loop devices
kpartx -dv "${loopdevice}"
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone wrong.
clean_build
