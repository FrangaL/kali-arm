#!/bin/bash
set -e

# This is Kali Linux ARM image for Raspberry Pi 2 v1.2/3/4/400 (64-bit) (Minimal)
# More information:
# - https://www.kali.org/docs/arm/raspberry-pi-2-1.2/
# - https://www.kali.org/docs/arm/raspberry-pi-3/
# - https://www.kali.org/docs/arm/raspberry-pi-4/
# - https://www.kali.org/docs/arm/raspberry-pi-400/

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"rpi4"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}-minimal"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"none"}

# Load common variables
include variables

# Checks script environment
include check

# Packages build list
include packages

# Load automatic proxy configuration
include proxy_apt

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

# Copy directory bsp into build dir
cp -rp bsp "${work_dir}"

# Third stage
cat << EOF > "${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get -y install ${packages} || eatmydata apt-get -y install --fix-broken
eatmydata apt-get -y install ${desktop_pkgs} ${extra} || eatmydata apt-get -y install --fix-broken

eatmydata apt-get -y --purge autoremove

# Linux console/keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
install -m644 /bsp/services/all/*.service /etc/systemd/system/
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

# Re4son's rpi-tft configurator
install -m755 /bsp/scripts/kalipi-tft-config /usr/bin/
/usr/bin/kalipi-tft-config -u

# Script mode wlan monitor START/STOP
install -m755 /bsp/scripts/monstart /usr/bin/
install -m755 /bsp/scripts/monstop /usr/bin/

# Install the kernel packages
echo "deb http://http.re4son-kernel.com/re4son kali-pi main" > /etc/apt/sources.list.d/re4son.list
wget -qO /etc/apt/trusted.gpg.d/kali_pi-archive-keyring.gpg https://re4son-kernel.com/keys/http/kali_pi-archive-keyring.gpg
eatmydata apt-get update
eatmydata apt-get -y install kalipi-kernel kalipi-bootloader kalipi-re4son-firmware kalipi-kernel-headers

# Regenerate the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot
systemctl enable smi-hack

# Copy script rpi-resizerootfs
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

# Enable rpi-resizerootfs first boot
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Copy in the bluetooth firmware
install -m644 /bsp/firmware/rpi/BCM43430A1.hcd -D /lib/firmware/brcm/BCM43430A1.hcd
# Copy rule and service
install -m644 /bsp/bluetooth/rpi/99-com.rules /etc/udev/rules.d/
install -m644 /bsp/bluetooth/rpi/hciuart.service /etc/systemd/system/

# Enable hciuart for bluetooth device
install -m755 /bsp/bluetooth/rpi/btuart /usr/bin/
systemctl enable hciuart

# Enable copying of user wpa_supplicant.conf file
systemctl enable copy-user-wpasupplicant

# Enable sshd by putting ssh or ssh.txt file in /boot
systemctl enable enable-ssh

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc

# Set a REGDOMAIN. This needs to be done or wireless may not work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/g' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/g' /etc/default/console-setup

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

# Configure Raspberry PI firmware
include rpi_firmware

# Compile Raspberry PI userland
include rpi_userland

# Choose a locale
set_locale "$locale"

# Clean system
include clean_system

# Define DNS server after last running systemd-nspawn
echo "nameserver 8.8.8.8" > "${work_dir}"/etc/resolv.conf

# Disable the use of http proxy in case it is enabled
disable_proxy

# Mirror & suite replacement
restore_mirror

# Reload sources.list
include sources.list

# systemd doesn't seem to be generating the fstab properly for some people, so let's create one
cat << EOF > "${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               $fstype    defaults,noatime  0       1
EOF

# Calculate the space to create the image and create
make_image

# Create the disk partitions it
parted -s "${current_dir}"/"${imagename}".img mklabel msdos
parted -s "${current_dir}"/"${imagename}".img mkpart primary fat32 1MiB "${bootsize}"MiB
parted -s -a minimal "${current_dir}"/"${imagename}".img mkpart primary "$fstype" "${bootsize}"MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
bootp="${loopdevice}p1"
rootp="${loopdevice}p2"

# Create file systems
log "Formating partitions" green
mkfs.vfat -n BOOT -F 32 "${bootp}"
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root/
mount "${rootp}" "${basedir}"/root
mkdir -p "${basedir}"/root/boot
mount "${bootp}" "${basedir}"/root/boot

log "Rsyncing rootfs into image file" green
rsync -HPavz -q --exclude boot "${work_dir}"/ "${basedir}"/root/
rsync -rtx -q "${work_dir}"/boot "${basedir}"/root/
# Start to unmount partition(s)
sync; sync
# sleep for 10 seconds, to let the cache settle after sync
sleep 10
# Unmount filesystem
umount -l "${bootp}"
umount -l "${rootp}"

# Check filesystem
dosfsck -w -r -a -t "$bootp"
e2fsck -y -f "$rootp"

# Remove loop device
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories
# Comment this out to keep things around if you want to see what may have gone wrong
clean_build
