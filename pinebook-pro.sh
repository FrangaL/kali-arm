#!/bin/bash -e
# This is the Pinebook Pro Kali ARM 64 bit build script - http://www.kali.org/get-kali
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"pinebook-pro"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

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
# Do *NOT* include wlan0 if using a desktop otherwise NetworkManager will ignore it.
#add_interface wlan0
# Copy directory bsp into build dir.
cp -rp bsp "${work_dir}"

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken
# Commented out for now, we don't want to install them due to the wifi device crashing
# and causing kernel panics, even with the latest from unstable Debian.
#eatmydata apt-get install -y dkms linux-image-arm64 u-boot-menu u-boot-rockchip
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

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

#Touchpad settings
install -m644 /bsp/xorg/50-pine64-pinebook-pro.touchpad.conf /etc/X11/xorg.conf.d/

# Saved audio settings
install -m644 /bsp/audio/pinebook-pro/asound.state /var/lib/alsa/asound.state

# And enable bluetooth
systemctl enable bluetooth

# Enable suspend2idle
sed -i s/"#SuspendState=mem standby freeze"/"SuspendState=freeze"/g /etc/systemd/sleep.conf

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

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

# Pull in the wifi and bluetooth firmware from manjaro's git repository.
cd ${work_dir}
git clone https://gitlab.manjaro.org/manjaro-arm/packages/community/ap6256-firmware.git
cd ap6256-firmware
mkdir brcm
cp BCM4345C5.hcd brcm/BCM.hcd
cp BCM4345C5.hcd brcm/BCM4345C5.hcd
cp nvram_ap6256.txt brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt
# Show all channels on 2.4 and 5GHz bands in all countries
# https://gitlab.manjaro.org/manjaro-arm/packages/community/ap6256-firmware/-/issues/2
sed -i -e 's/ccode.*/ccode=all/' brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt
cp fw_bcm43456c5_ag.bin brcm/brcmfmac43456-sdio.bin
cp brcmfmac43456-sdio.clm_blob brcm/brcmfmac43456-sdio.clm_blob
mkdir -p ${work_dir}/lib/firmware/brcm/
cp -a brcm/* ${work_dir}/lib/firmware/brcm/
cd ${current_dir}
rm -rf ${work_dir}/ap6256-firmware

# Time to build the kernel
# 5.14.1 from linux-stable
cd ${work_dir}/usr/src
git clone  -b linux-5.14.y --depth 1 git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git ${work_dir}/usr/src/linux
cd linux
touch .scmversion
# Lots o patches, for added support nicked from Manjaro
#patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/kali-wifi-injection-5.9.patch
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0001-net-smsc95xx-Allow-mac-address-to-be-set-as-a-parame.patch"             #All
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0002-arm64-dts-amlogic-add-support-for-Radxa-Zero.patch"                     #Radxa Zero
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0003-arm64-dts-allwinner-add-hdmi-sound-to-pine-devices.patch"               #Pine64
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0004-arm64-dts-allwinner-add-ohci-ehci-to-h5-nanopi.patch"                   #Nanopi Neo Plus 2
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0005-drm-bridge-analogix_dp-Add-enable_psr-param.patch"                      #Pinebook Pro
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0006-gpu-drm-add-new-display-resolution-2560x1440.patch"                     #Odroid
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0007-nuumio-panfrost-Silence-Panfrost-gem-shrinker-loggin.patch"             #Panfrost
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0008-arm64-dts-rockchip-Add-Firefly-Station-p1-support.patch"                #Firelfy Station P1
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0009-typec-displayport-some-devices-have-pin-assignments-reversed.patch"     #DP Alt Mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0010-usb-typec-add-extcon-to-tcpm.patch"                                     #DP Alt Mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0011-arm64-rockchip-add-DP-ALT-rockpro64.patch"                              #DP Alt mode - RockPro64
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0012-ayufan-drm-rockchip-add-support-for-modeline-32MHz-e.patch"             #DP Alt mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0013-rk3399-rp64-pcie-Reimplement-rockchip-PCIe-bus-scan-delay.patch"        #RockPro64
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0014-phy-rockchip-typec-Set-extcon-capabilities.patch"                       #DP Alt mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0015-usb-typec-altmodes-displayport-Add-hacky-generic-altmode.patch"         #DP Alt mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0018-drm-meson-add-YUV422-output-support.patch"                              #G12B
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0019-arm64-dts-meson-add-initial-Beelink-GT1-Ultimate-dev.patch"             #Beelink
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0020-add-ugoos-device.patch"                                                 #Ugoos
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0021-drm-panfrost-Handle-failure-in-panfrost_job_hw_submit.patch"            #AMLogic
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0022-arm64-dts-rockchip-Add-pcie-bus-scan-delay-to-rockpr.patch"             #RockPro64
# Pinebook Pro patches
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0016-arm64-dts-rockchip-add-typec-extcon-hack.patch"                         #DP Alt mode
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0017-arm64-dts-rockchip-setup-USB-type-c-port-as-dual-data-role.patch"       #USB-C charging
# Pinebook, PinePhone and PineTab patches
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0001-Bluetooth-Add-new-quirk-for-broken-local-ext-features.patch"            #Bluetooth
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0002-Bluetooth-btrtl-add-support-for-the-RTL8723CS.patch"                    #Bluetooth
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0003-arm64-allwinner-a64-enable-Bluetooth-On-Pinebook.patch"                 #Bluetooth
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0004-arm64-dts-allwinner-enable-bluetooth-pinetab-pinepho.patch"             #Bluetooth
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0005-staging-add-rtl8723cs-driver.patch"                                     #Wifi
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0006-pinetab-accelerometer.patch"                                            #accelerometer
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0007-enable-jack-detection-pinetab.patch"                                    #Audio
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0008-enable-hdmi-output-pinetab.patch"                                       #HDMI
patch -Np1 -i "${current_dir}/patches/pinebook-pro/pbp-5.14/0009-drm-panel-Adjust-sync-values-for-Feixin-K101-IM2BYL02-panel.patch"      #Display

cp ${current_dir}/kernel-configs/pinebook-pro-5.14.config .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= -j$(nproc)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= INSTALL_MOD_PATH=${work_dir} modules_install
cp arch/arm64/boot/Image ${work_dir}/boot
cp arch/arm64/boot/dts/rockchip/rk3399-pinebook-pro.dtb ${work_dir}/boot
# clean up because otherwise we leave stuff around that causes external modules
# to fail to build.
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper
## And re-setup the .config file, and make a backup in the previous directory
cp ${current_dir}/kernel-configs/pinebook-pro-5.14.config .config
cp ${current_dir}/kernel-configs/pinebook-pro-5.14.config ../pinebook-pro-5.14.config


# Fix up the symlink for building external modules
# kernver is used to we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules)
cd ${work_dir}/lib/modules/${kernver}/
rm build
rm source
ln -s /usr/src/linux build
ln -s /usr/src/linux source
cd ${current_dir}

cat << '__EOF__' > ${work_dir}/boot/boot.txt
# MAC address (use spaces instead of colons)
setenv macaddr da 19 c8 7a 6d f4

part uuid ${devtype} ${devnum}:${bootpart} uuid
setenv bootargs console=tty1 console=ttyS2,1500000 root=PARTUUID=${uuid} rw rootwait video=eDP-1:1920x1080@60
setenv fdtfile rk3399-pinebook-pro.dtb

if load ${devtype} ${devnum}:${bootpart} ${kernel_addr_r} /boot/Image; then
  if load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} /boot/${fdtfile}; then
    fdt addr ${fdt_addr_r}
    fdt resize
    fdt set /ethernet@fe300000 local-mac-address "[${macaddr}]"
    if load ${devtype} ${devnum}:${bootpart} ${ramdisk_addr_r} /boot/initramfs-linux.img; then
      # This upstream Uboot doesn't support compresses cpio initrd, use kernel option to
      # load initramfs
      setenv bootargs ${bootargs} initrd=${ramdisk_addr_r},20M ramdisk_size=10M
    fi;
    booti ${kernel_addr_r} - ${fdt_addr_r};
  fi;
fi
__EOF__
cd ${work_dir}/boot
mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d boot.txt boot.scr

cd ${current_dir}

# Enable brightness up/down and sleep hotkeys and attempt to improve
# touchpad performance
mkdir -p ${work_dir}/etc/udev/hwdb.d/
cat << 'EOF' > ${work_dir}/etc/udev/hwdb.d/10-usb-kbd.hwdb
evdev:input:b0003v258Ap001E*
  KEYBOARD_KEY_700a5=brightnessdown
  KEYBOARD_KEY_700a6=brightnessup
  KEYBOARD_KEY_70066=sleep
  # Supposed to improve performance of touchpad
  EVDEV_ABS_00=::15
  EVDEV_ABS_01=::15
  EVDEV_ABS_35=::15
  EVDEV_ABS_36=::15
EOF

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

# FUTURE: Move to debian u-boot when it works properly.
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot.
# We do this down here because we don't know the UUID until after the image is created.
#sed -i -e "0,/root=.*/s//root=UUID=$(blkid -s UUID -o value ${rootp}) rootfstype=$fstype console=ttyS0,115200 console=tty1 consoleblank=0 rw quiet rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf

log "Rsyncing rootfs into image file" green
rsync -HPavz -q "${work_dir}"/ "${basedir}"/root/
sync

## Nick the u-boot from Manjaro ARM to see if my compilation was somehow
## screwing things up.
cp ${current_dir}/bsp/bootloader/pinebook-pro/idbloader.img ${current_dir}/bsp/bootloader/pinebook-pro/trust.img ${current_dir}/bsp/bootloader/pinebook-pro/uboot.img ${basedir}/root/boot/
dd if=${current_dir}/bsp/bootloader/pinebook-pro/idbloader.img of=${loopdevice} seek=64 conv=notrunc
dd if=${current_dir}/bsp/bootloader/pinebook-pro/uboot.img of=${loopdevice} seek=16384 conv=notrunc
dd if=${current_dir}/bsp/bootloader/pinebook-pro/trust.img of=${loopdevice} seek=24576 conv=notrunc

#TARGET="/usr/lib/u-boot/pinebook-pro-rk3399" /usr/bin/u-boot-install-rockchip ${loopdevice}

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
