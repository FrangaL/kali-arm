#!/bin/bash
set -e

# This is the FriendlyARM NanoPi2 Kali ARM build script - http://nanopi.io/
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/nanopi2-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-nanopi2}
# Size of image in megabytes (Default is 4500=4.5GB)
size=4500
# Suite to use.
# Valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
# A release is done against kali-last-snapshot, but if you're building your own, you'll probably want to build
# kali-rolling.
suite=kali-rolling

# Generate a random machine name to be used.
machine=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# Make sure that the cross compiler can be found in the path before we do
# anything else, that way the builds don't fail half way through.
export CROSS_COMPILE=arm-linux-gnueabihf-
if [ $(compgen -c $CROSS_COMPILE | wc -l) -eq 0 ] ; then
    echo "Missing cross compiler. Set up PATH according to the README"
    exit 1
fi
# Unset CROSS_COMPILE so that if there is any native compiling needed it doesn't
# get cross compiled.
unset CROSS_COMPILE

# Package installations for various sections.
# This will build a minimal XFCE Kali system with the top 10 tools.
# This is the section to edit if you would like to add more packages.
# See http://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
# use. You can also install packages, using just the package name, but keep in
# mind that not all packages work on ARM! If you specify one of those, the
# script will throw an error, but will still continue on, and create an unusable
# image, keep that in mind.

arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils vboot-kernel-utils"
base="apt-transport-https apt-utils console-setup e2fsprogs firmware-linux firmware-realtek firmware-atheros firmware-libertas firmware-brcm80211 ifupdown initramfs-tools iw kali-defaults man-db mlocate netcat-traditional net-tools parted psmisc rfkill screen snmpd snmp sudo tftp tmux unrar usbutils vim wget zerofree"
desktop="kali-menu fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev xserver-xorg-input-evdev xserver-xorg-input-synaptics"
tools="aircrack-ng crunch cewl dnsrecon dnsutils ethtool exploitdb hydra john libnfc-bin medusa metasploit-framework mfoc ncrack nmap passing-the-hash proxychains recon-ng sqlmap tcpdump theharvester tor tshark usbutils whois windows-binaries winexe wpscan wireshark"
services="apache2 atftpd openssh-server openvpn tightvncserver"
extras="firefox-esr xfce4-terminal wpasupplicant python3-smbus i2c-tools bluez bluez-firmware xfonts-terminus"

packages="${arm} ${base} ${services}"
architecture="armhf"
# If you have your own preferred mirrors, set them here.
# After generating the rootfs, we set the sources.list to the default settings.
mirror=http.kali.org

# Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
# to unset it.
#export http_proxy="http://localhost:3142/"

mkdir -p "${basedir}"
cd "${basedir}"

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring --arch ${architecture} ${suite} kali-${architecture} http://${mirror}/kali

cp /usr/bin/qemu-arm-static kali-${architecture}/usr/bin/

LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /debootstrap/debootstrap --second-stage

mkdir -p kali-${architecture}/etc/apt/
cat << EOF > kali-${architecture}/etc/apt/sources.list
deb http://${mirror}/kali ${suite} main contrib non-free
EOF

echo "${hostname}" > kali-${architecture}/etc/hostname

cat << EOF > kali-${architecture}/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

mkdir -p kali-${architecture}/etc/network/
cat << EOF > kali-${architecture}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# This prevents NetworkManager from attempting to use this
# device to connect to wifi, since NM doesn't show which device is which.
# Unfortunately, it still SHOWS the device, just that it's not managed.
iface p2p0 inet manual
EOF

cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

#mount -t proc proc kali-${architecture}/proc
#mount -o bind /dev/ kali-${architecture}/dev/
#mount -o bind /dev/pts kali-${architecture}/dev/pts

cat << EOF > kali-${architecture}/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

mkdir -p kali-${architecture}/usr/lib/systemd/system/
cat << 'EOF' > kali-${architecture}/usr/lib/systemd/system/regenerate_ssh_host_keys.service
[Unit]
Description=Regenerate SSH host keys
Before=ssh.service
[Service]
Type=oneshot
ExecStartPre=-/bin/dd if=/dev/hwrng of=/dev/urandom count=1 bs=4096
ExecStartPre=-/bin/sh -c "/bin/rm -f -v /etc/ssh/ssh_host_*_key*"
ExecStart=/usr/bin/ssh-keygen -A -v
ExecStartPost=/bin/sh -c "for i in /etc/ssh/ssh_host_*_key*; do actualsize=$(wc -c <\"$i\") ;if [ $actualsize -eq 0 ]; then echo size is 0 bytes ; exit 1 ; fi ; done ; /bin/systemctl disable regenerate_ssh_host_keys"
[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/regenerate_ssh_host_keys.service

cat << EOF > kali-${architecture}/usr/lib/systemd/system/smi-hack.service
[Unit]
Description=shared-mime-info update hack
Before=regenerate_ssh_host_keys.service
[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/bin/sh -c "rm -rf /etc/ssl/certs/*.pem && dpkg -i /root/ca-certificates_20190110_all.deb /root/fontconfig_2.13.1-2_armhf.deb /root/libgdk-pixbuf2.0-0_2.38.1+dfsg-1_armhf.deb"
ExecStart=/bin/sh -c "dpkg-reconfigure shared-mime-info"
ExecStart=/bin/sh -c "dpkg-reconfigure xfonts-base"
ExecStart=/bin/sh -c "rm -f /root/*.deb"
ExecStartPost=/bin/systemctl disable smi-hack

[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/smi-hack.service

cat << EOF > kali-${architecture}/usr/lib/systemd/system/rpiwiggle.service
[Unit]
Description=Resize filesystem
After=regenerate_ssh_host_keys.service
[Service]
Type=oneshot
ExecStart=/root/scripts/rpi-wiggle.sh
ExecStartPost=/bin/systemctl disable rpiwiggle
[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/rpiwiggle.service

cat << EOF > kali-${architecture}/third-stage
#!/bin/bash
set -e
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update
apt-get --yes --allow-change-held-packages install locales-all

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd
rm -f /etc/udev/rules.d/70-persistent-net.rules
export DEBIAN_FRONTEND=noninteractive
# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice.
apt-get --yes --allow-change-held-packages install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages dist-upgrade
apt-get --yes --allow-change-held-packages autoremove

# Because copying in authorized_keys is hard for people to do, let's make the
# image insecure and enable root login with a password.

sed -i -e 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
systemctl enable ssh

# Resize FS on first run (hopefully)
systemctl enable rpiwiggle

# Copy bashrc
cp  /etc/skel/.bashrc /root/.bashrc

cd /root
apt download ca-certificates
apt download libgdk-pixbuf2.0-0
apt download fontconfig

rm -f /usr/sbin/policy-rc.d
rm -f /usr/sbin/invoke-rc.d
dpkg-divert --remove --rename /usr/sbin/invoke-rc.d

rm -f /third-stage
EOF

chmod 755 kali-${architecture}/third-stage
LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /third-stage

cat << EOF > kali-${architecture}/cleanup
#!/bin/bash
rm -rf /root/.bash_history
apt-get update
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*
EOF

chmod 755 kali-${architecture}/cleanup
LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /cleanup

#umount kali-${architecture}/proc/sys/fs/binfmt_misc
#umount kali-${architecture}/dev/pts
#umount kali-${architecture}/dev/
#umount kali-${architecture}/proc

# Serial console settings.
# (No auto login)
echo 'T1:12345:respawn:/sbin/agetty 115200 ttyAMA0 vt100' >> "${basedir}"/kali-${architecture}/etc/inittab

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

# We need an older gcc because of kernel age.
cd "${basedir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section.
git clone --depth 1 https://github.com/friendlyarm/linux-3.4.y -b nanopi2-lollipop-mr1 "${basedir}"/kali-${architecture}/usr/src/kernel
cd "${basedir}"/kali-${architecture}/usr/src/kernel
git rev-parse HEAD > "${basedir}"/kali-${architecture}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm
export CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/mac80211.patch
# Ugh, this patch is needed because the ethernet driver uses parts of netdev
# from a newer kernel?
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/0001-Remove-define.patch
cp "${basedir}"/../kernel-configs/nanopi2* "${basedir}"/kali-${architecture}/usr/src/
cp ../nanopi2-vendor.config .config
make -j $(grep -c processor /proc/cpuinfo)
make uImage
make modules_install INSTALL_MOD_PATH="${basedir}"/kali-${architecture}/
# We copy this twice because you can't do symlinks on fat partitions.
# Also, the uImage known as uImage.hdmi is used by uboot if hdmi output is
# detected.
cp arch/arm/boot/uImage "${basedir}"/kali-${architecture}/boot/uImage-720p
cp arch/arm/boot/uImage "${basedir}"/kali-${architecture}/boot/uImage.hdmi
# Friendlyarm suggests staying at 720p for now.
#cp ../nanopi2-1080p.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage-1080p
#cp ../nanopi2-lcd-hd101.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage-hd101
#cp ../nanopi2-lcd-hd700.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage-hd700
#cp ../nanopi2-lcd.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
# The default uImage is for lcd usage, so we copy the lcd one twice
# so people have a backup in case they overwrite uImage for some reason.
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage-s70
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage.lcd
#cp arch/arm/boot/uImage "${basedir}"/bootp/uImage
cd "${basedir}"

# FriendlyARM suggest using backports for wifi with their devices, and the
# recommended version is the 4.4.2.
cd "${basedir}"/kali-${architecture}/usr/src/
#wget https://www.kernel.org/pub/linux/kernel/projects/backports/stable/v4.4.2/backports-4.4.2-1.tar.xz
#tar -xf backports-4.4.2-1.tar.xz
git clone https://github.com/friendlyarm/wireless
cd wireless
cd backports-4.4.2-1
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/kali-wifi-injection-4.4.patch
cd ..
#cp "${basedir}"/../kernel-configs/backports.config .config
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(grep -c processor /proc/cpuinfo) KLIB_BUILD="${basedir}"/root/usr/src/kernel KLIB="${basedir}"/root
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KLIB_BUILD="${basedir}"/root/usr/src/kernel KLIB="${basedir}"/root INSTALL_MOD_PATH="${basedir}"/root install
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KLIB_BUILD="${basedir}"/root/usr/src/kernel KLIB="${basedir}"/root mrproper
#cp "${basedir}"/../kernel-configs/backports.config .config
XCROSS="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- ANDROID=n ./build.sh -k "${basedir}"/kali-${architecture}/usr/src/kernel -c nanopi2 -o "${basedir}"/kali-${architecture}
cd "${basedir}"

# Now we clean up the kernel build
cd "${basedir}"/kali-${architecture}/usr/src/kernel
make mrproper
cd "${basedir}"

# Copy over the firmware for the nanopi2/3 wifi.
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon.
mkdir -p "${basedir}"/kali-${architecture}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${basedir}/kali-${architecture}/lib/firmware/ap6212/config.txt
cd "${basedir}"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls "${basedir}"/kali-${architecture}/lib/modules/)
cd "${basedir}"/kali-${architecture}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${basedir}"

cp "${basedir}"/../misc/zram "${basedir}"/kali-${architecture}/etc/init.d/zram
chmod 755 "${basedir}"/kali-${architecture}/etc/init.d/zram

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config


RAW_SIZE_MB=${size}
BLOCK_SIZE=1024
let RAW_SIZE=(${RAW_SIZE_MB}*1000*1000)/${BLOCK_SIZE}

# Create the disk and partition it
echo "Creating image file ${imagename}.img"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=${BLOCK_SIZE} count=0 seek=${RAW_SIZE}
parted ${imagename}.img --script -- mklabel msdos
parted ${imagename}.img --script -- mkpart primary ext4 2048s 264191s
parted ${imagename}.img --script -- mkpart primary ext4 264192s 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.ext4 ${bootp}
mkfs.ext4 -O ^64bit -O ^flex_bg -O ^metadata_csum ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root
mkdir -p "${basedir}"/root/boot
mount ${bootp} "${basedir}"/root/boot

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${basedir}"/kali-${architecture}/ "${basedir}"/root/

# Unmount partitions
sync
umount -l ${bootp}
umount -l ${rootp}
kpartx -dv ${loopdevice}

# Samsung bootloaders must be signed.
# These are the same steps that are done by
# https://github.com/friendlyarm/sd-fuse_nanopi2/blob/master/fusing.sh

# Download the latest prebuilt from the above url.
mkdir -p "${basedir}"/bootloader
cd "${basedir}"/bootloader
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/2ndboot.bin?raw=true' -O 2ndboot.bin
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/boot.TBI?raw=true' -O boot.TBI
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/bootloader' -O bootloader
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bl1-mmcboot.bin
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bl_mon.img
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bootloader.img # This is u-boot
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/loader-mmc.img
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/tools/fw_printenv
chmod 755 fw_printenv
ln -s fw_printenv fw_setenv

dd if=2ndboot.bin of=${loopdevice} bs=512 seek=1
dd if=boot.TBI of=${loopdevice} bs=512 seek=64 count=1
dd if=bootloader of=${loopdevice} bs=512 seek=65

cat << EOF > ${basedir}/bootloader/env.conf
# U-Boot environment for Debian, Ubuntu
#
# Copyright (C) Guangzhou FriendlyARM Computer Tech. Co., Ltd.
# (http://www.friendlyarm.com)
#

bootargs	console=ttyAMA0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw consoleblank=0 net.ifnames=0
bootdelay	1
EOF

./fw_setenv ${loopdevice} -s env.conf

sync

cd "${basedir}"

losetup -d ${loopdevice}

# Don't pixz on 32bit, there isn't enough memory to compress the images.
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
echo "Compressing ${imagename}.img"
pixz "${basedir}"/${imagename}.img "${basedir}"/../${imagename}.img.xz
rm "${basedir}"/${imagename}.img
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Clean up the build system"
rm -rf "${basedir}"
