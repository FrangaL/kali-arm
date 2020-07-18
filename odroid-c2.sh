#!/bin/bash
set -e

# This is the HardKernel ODROID C2 Kali ARM64 build script - http://hardkernel.com/main/main.php
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

# Uncomment to activate debug
# debug=true

if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"arm64"}
# Generate a random machine name to be used.
machine=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c16 ; echo)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-odroidc2}
# Suite to use, valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
suite=${suite:-"kali-rolling"}
# Free space rootfs in MiB
free_space="300"
# /boot partition in MiB
bootsize="128"
# If you have your own preferred mirrors, set them here.
mirror="http://kali.download/kali"
# Gitlab url Kali repository
kaligit="https://gitlab.com/kalilinux"
# Github raw url
githubraw="https://raw.githubusercontent.com"

# Check EUID=0 you can run any binary as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Pass version number
if [[ $# -eq 0 ]] ; then
  echo "Please pass version number, e.g. $0 2.0, and (if you want) a hostname, default is kali"
  exit 0
fi

# Check exist bsp directory.
if [ ! -e "bsp" ]; then
  echo "Error: missing bsp directory structure"
  echo "Please clone the full repository ${kaligit}/build-scripts/kali-arm"
  exit 255
fi

# Current directory
current_dir="$(pwd)"
# Base directory
basedir=${current_dir}/odroidc2-"$1"
# Working directory
work_dir="${basedir}/kali-${architecture}"

# Check directory build
if [ -e "${basedir}" ]; then
  echo "${basedir} directory exists, will not continue"
  exit 1
elif [[ ${current_dir} =~ [[:space:]] ]]; then
  echo "The directory "\"${current_dir}"\" contains whitespace. Not supported."
  exit 1
else
  echo "The basedir thinks it is: ${basedir}"
  mkdir -p ${basedir}
fi

components="main,contrib,non-free"
arm="kali-linux-arm ntpdate"
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw  man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree u-boot-amlogic u-boot-menu linux-image-arm64"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xfonts-terminus xinput"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware fbset kali-linux-core libnss-systemd libssl-dev triggerhappy"
#kali="build-essential debhelper devscripts dput lintian quilt git-buildpackage gitk dh-make sbuild"

packages="${arm} ${base} ${services}"

# Automatic configuration to use an http proxy, such as apt-cacher-ng.
# You can turn off automatic settings by uncommenting apt_cacher=off.
# apt_cacher=off
# By default the proxy settings are local, but you can define an external proxy.
# proxy_url="http://external.intranet.local"
apt_cacher=${apt_cacher:-"$(lsof -i :3142|cut -d ' ' -f3 | uniq | sed '/^\s*$/d')"}
if [ -n "$proxy_url" ]; then
  export http_proxy=$proxy_url
elif [ "$apt_cacher" = "apt-cacher-ng" ] ; then
  if [ -z "$proxy_url" ]; then
    proxy_url=${proxy_url:-"http://127.0.0.1:3142/"}
    export http_proxy=$proxy_url
  fi
fi

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring \
  --components=${components} --arch ${architecture} ${suite} ${work_dir} http://http.kali.org/kali

# systemd-nspawn enviroment
systemd-nspawn_exec(){
  qemu_bin=/usr/bin/qemu-aarch64-static
  LANG=C systemd-nspawn -q --bind-ro ${qemu_bin} -M ${machine} -D ${work_dir} "$@"
}

# debootstrap second stage
systemd-nspawn_exec /debootstrap/debootstrap --second-stage

cat << EOF > ${work_dir}/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

# Set hostname
echo "${hostname}" > ${work_dir}/etc/hostname

# So X doesn't complain, we add kali to hosts
cat << EOF > ${work_dir}/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Disable IPv6
cat << EOF > ${work_dir}/etc/modprobe.d/ipv6.conf
# Don't load ipv6 by default
alias net-pf-10 off
EOF

cat << EOF > ${work_dir}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# DNS server
echo "nameserver 8.8.8.8" > ${work_dir}/etc/resolv.conf

# Copy directory bsp into build dir.
cp -rp bsp ${work_dir}

export MALLOC_CHECK_=0 # workaround for LP: #520465

# Enable the use of http proxy in third-stage in case it is enabled.
if [ -n "$proxy_url" ]; then
  echo "Acquire::http { Proxy \"$proxy_url\" };" > ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

# Disable RESUME (suspend/resume is currently broken anyway!) which speeds up boot massively.
mkdir -p ${work_dir}/etc/initramfs-tools/conf.d/
cat << EOF > ${work_dir}/etc/initramfs-tools/conf.d/resume
RESUME=none
EOF

cat << EOF > ${work_dir}/third-stage
#!/bin/bash -e
export DEBIAN_FRONTEND=noninteractive
export RUNLEVEL=1
ln -sf /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update

apt-get -y install git-core binutils ca-certificates locales console-common less nano git cmake

# Create kali user with kali password... but first, we need to manually make some groups because they don't yet exist...
# This mirrors what we have on a pre-installed VM, until the script works properly to allow end users to set up their own... user.
# However we leave off floppy, because who a) still uses them, and b) attaches them to an SBC!?
# And since a lot of these have serial devices of some sort, dialout is added as well.
# scanner, lpadmin and bluetooth have to be added manually because they don't
# yet exist in /etc/group at this point.
groupadd -r -g 118 bluetooth
groupadd -r -g 113 lpadmin
groupadd -r -g 122 scanner
groupadd -g 1000 kali

useradd -m -u 1000 -g 1000 -G sudo,audio,bluetooth,cdrom,dialout,dip,lpadmin,netdev,plugdev,scanner,video,kali -s /bin/bash kali
echo "kali:kali" | chpasswd

aptops="--allow-change-held-packages -o dpkg::options::=--force-confnew"

# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice.
apt-get install -y \$aptops ${packages} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${packages} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get install -y \$aptops systemd-timesyncd || apt-get --yes --fix-broken install
apt-get dist-upgrade -y \$aptops

apt-get -y --allow-change-held-packages --purge autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/
cp -p /bsp/services/odroid-c2/*.service /etc/systemd/system/

# Run u-boot-update to generate the extlinux.conf file - we will replace this later, via sed, to point to the correct root partition (hopefully?)
u-boot-update

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
systemctl enable ssh

# Copy bashrc
cp  /etc/skel/.bashrc /root/.bashrc

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

rm -f /usr/sbin/policy-rc.d
unlink /usr/sbin/invoke-rc.d
EOF
chmod 755 ${work_dir}/third-stage

systemd-nspawn_exec /third-stage

# Clean system
systemd-nspawn_exec << EOF
rm -f /0
rm -rf /bsp
fc-cache -frs
rm -rf /tmp/*
rm -rf /etc/*-
rm -rf /hs_err*
rm -rf /userland
rm -rf /opt/vc/src
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*.data-old
history -c
EOF
#Clear all logs
for logs in `find $work_dir/var/log -type f`; do > $logs; done

# Disable the use of http proxy in case it is enabled.
if [ -n "$proxy_url" ]; then
  unset http_proxy
  rm -rf ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

cat << EOF > ${work_dir}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# For some reason the latest modesetting driver (part of xorg server)
# seems to cause a lot of jerkiness.  Using the fbdev driver is not
# ideal but it's far less frustrating to work with.
mkdir -p ${work_dir}/etc/X11/xorg.conf.d
cp "${basedir}"/bsp/xorg/20-meson.conf ${work_dir}}/etc/X11/xorg.conf.d/

# 1366x768 is sort of broken on the ODROID-C2, not sure where the issue is, but
# we can work around it by setting the resolution to 1360x768.
# This requires 2 files, a script and then something for lightdm to use.
# I do not have anything set up for the console though, so that's still broken for now.
mkdir -p ${work_dir}}/usr/local/bin
cat << 'EOF' > ${work_dir}}/usr/local/bin/xrandrscript.sh
#!/usr/bin/env bash

resolution=$(xdpyinfo | awk '/dimensions:/ { print $2; exit }')

if [[ "$resolution" == "1366x768" ]]; then
    xrandr --newmode "1360x768_60.00"   84.75  1360 1432 1568 1776  768 771 781 798 -hsync +vsync
    xrandr --addmode HDMI-1 1360x768_60.00
    xrandr --output HDMI-1 --mode  1360x768_60.00
fi
EOF
chmod 755 ${work_dir}}/usr/local/bin/xrandrscript.sh

mkdir -p ${work_dir}}/usr/share/lightdm/lightdm.conf.d/
cat << EOF > ${work_dir}/usr/share/lightdm/lightdm.conf.d/60-xrandrscript.conf
[SeatDefaults]
display-setup-script=/usr/local/bin/xrandrscript.sh
session-setup-script=/usr/local/bin/xrandrscript.sh
EOF

# Calculate the space to create the image.
free_space=$((${free_space}*1024))
bootstart=$((${bootsize}*1024/1000*2*1024/2))
bootend=$((${bootstart}+1024))
rootsize=$(du -s --block-size KiB ${work_dir} --exclude boot | cut -f1)
rootsize=$((${free_space}+${rootsize//KiB/ }/1000*2*1024/2))
raw_size=$((${free_space}+${rootsize}+${bootstart}))

# Create the disk and partition it
echo "Creating image file ${imagename}.img"
dd if=/dev/zero of=${basedir}/${imagename}.img bs=1KiB count=0 seek=${raw_size} && sync
parted "${basedir}"/${imagename}.img --script -- mklabel msdos
parted "${basedir}"/${imagename}.img --script -- mkpart primary ext3 32MiB 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p1

# Create file systems
mkfs.ext3 -L ROOTFS -O ^64bit,^flex_bg,^metadata_csum ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p ${basedir}/root
mount ${rootp} ${basedir}/root


#sed -i -e "s/root=\/dev\/mmcblk0p2/root=PARTUUID=$(blkid -s PARTUUID -o value ${rootp})/g" "${basedir}"/kali-${architecture}/boot/boot.cmd
# Let's get the blkid of the rootpartition, and sed it out in the extlinux.conf file.
# 0, means only replace the first instance.  This does mean that the second instance won't be replaced, but most people aren't going to use that(fingers crossed)
# We also set it to rw instead of ro, because for whatever reason, it's not remounting rw when the initramfs->rootfs switch happens
sed -i -e "0,/root=.*/s//root=UUID=$(blkid -s UUID -o value ${rootp}) rw quiet/g" ${work_dir}}/boot/extlinux/extlinux.conf

# Create an fstab so that we don't mount / read-only.
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               ext3    errors=remount-ro 0       1" >> ${work_dir}}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${basedir}/root/

# Unmount partitions
# Sync before unmounting to ensure everything is written
sync
umount -l ${rootp}
kpartx -dv ${loopdevice}

# We are gonna use as much open source as we can here, hopefully we end up with a nice
# mainline u-boot and signed bootloader - unfortunately, due to the way this is packaged up
# we have to clone two different u-boot repositories - the one from HardKernel which
# has the bootloader binary blobs we need, and the denx mainline u-boot repository.
# Let the fun begin.

# Unset these because we're building on the host.
unset ARCH
unset CROSS_COMPILE

mkdir -p ${basedir}/bootloader
cd ${basedir}/bootloader
git clone https://github.com/afaerber/meson-tools --depth 1
git clone git://git.denx.de/u-boot --depth 1
git clone https://github.com/hardkernel/u-boot -b odroidc2-v2015.01 u-boot-hk --depth 1

# First things first, let's build the meson-tools, of which, we only really need amlbootsig
cd ${basedir}/bootloader/meson-tools/
make
# Now we need to build fip_create
cd ${basedir}/bootloader/u-boot-hk/tools/fip_create
HOSTCC=cc HOSTLD=ld make

cd ${basedir}/bootloader/u-boot/
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- odroid-c2_defconfig
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu-

# Now the real fun... keeping track of file locations isn't fun, and i should probably move them to
# one single directory, but since we're not keeping these things around afterwards, it's fine to
# leave them where they are.
# See:
# https://forum.odroid.com/viewtopic.php?t=26833
# https://github.com/nxmyoz/c2-overlay/blob/master/Readme.md
# for the inspirations for it.  Specifically Adrian's posts got us closest.

# This is funky, but in the end, it should do the right thing.
cd ${basedir}/bootloader/
# Create the fip.bin
./u-boot-hk/tools/fip_create/fip_create --bl30 ./u-boot-hk/fip/gxb/bl30.bin \
--bl301 ./u-boot-hk/fip/gxb/bl301.bin --bl31 ./u-boot-hk/fip/gxb/bl31.bin \
--bl33 u-boot/u-boot.bin fip.bin

# Create the stage2 bootloader thingie?
cat ./u-boot-hk/fip/gxb/bl2.package fip.bin > boot_new.bin
# Now sign it, and call it u-boot.bin
./meson-tools/amlbootsig boot_new.bin u-boot.bin
# Now strip a portion of it off, and put it in the sd_fuse directory
dd if=u-boot.bin of=./u-boot-hk/sd_fuse/u-boot.bin bs=512 skip=96
# Finally, write it to the loopdevice so we have our bootloader on the card.
cd ./u-boot-hk/sd_fuse
./sd_fusing.sh ${loopdevice}
sync
cd ${basedir}

losetup -d ${loopdevice}

# Don't pixz on 32bit, there isn't enough memory to compress the images.
if [ $(arch) == 'x86_64' ]; then
  echo "Compressing ${imagename}.img"
  rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) # Randowm name group
  cgcreate -g cpu:/cpulimit-${rand} # Name of group
  cgset -r cpu.shares=800 cpulimit-${rand} # Max 1024
  cgset -r cpu.cfs_quota_us=80000 cpulimit-${rand} # Max 100000
  cgexec -g cpu:cpulimit-${rand} pixz -p 2 "${basedir}"/${imagename}.img ${imagename}.img.xz # -p Nº cpu cores use
  cgdelete cpu:/cpulimit-${rand} # Delete group
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Cleaning up the temporary build files..."
rm -rf "${basedir}"