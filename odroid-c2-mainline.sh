#!/bin/bash
set -e

# This is the HardKernel ODROID C2 Kali ARM64 build script - http://hardkernel.com/main/main.php
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/odroidc2-mainline-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-odroidc2-mainline}
# Size of image in megabytes (Default is 14000=14GB)
size=14000
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
export CROSS_COMPILE=aarch64-linux-gnu-
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

# The package "fbset" is required to init the display.
# The video needs to be "kicked" before xorg starts, otherwise the video shows
# up in a weird state.
# DO NOT REMOVE IT FROM THE PACKAGE LIST.

arm="kali-inux-arm ntpdate"
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw  man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xfonts-terminus xinput"
tools="kali-tools-top10 wireshark"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware fbset kali-linux-core libnss-systemd libssl-dev triggerhappy"
#kali="build-essential debhelper devscripts dput lintian quilt git-buildpackage gitk dh-make sbuild"

packages="${arm} ${base} ${services}"
architecture="arm64"
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

cp /usr/bin/qemu-aarch64-static kali-${architecture}/usr/bin/

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
cp "${basedir}"/../bsp/services/all/*.service kali-${architecture}/usr/lib/systemd/system/
cp "${basedir}"/../bsp/services/odroid-c2/*.service kali-${architecture}/usr/lib/systemd/system/

cat << EOF > kali-${architecture}/third-stage
#!/bin/bash
set -e
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git

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

export DEBIAN_FRONTEND=noninteractive
# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice.
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew dist-upgrade
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew autoremove

# Because copying in authorized_keys is hard for people to do, let's make the
# image insecure and enable root login with a password.
echo "Making the image insecure"
sed -i -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack

# Resize FS on first run (hopefully)
#systemctl enable rpiwiggle

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
systemctl enable ssh

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

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# For some reason the latest modesetting driver (part of xorg server)
# seems to cause a lot of jerkiness.  Using the fbdev driver is not
# ideal but it's far less frustrating to work with.
mkdir -p "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d
cat << EOF > "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/20-fbdev.conf
Section "Device"
    Identifier      "Meson drm driver"
    Driver          "modesetting"
    Option          "AccelMethod"   "none"
EndSection
EOF

# 1366x768 is sort of broken on the ODROID-C2, not sure where the issue is, but
# we can work around it by setting the resolution to 1360x768.
# This requires 2 files, a script and then something for lightdm to use.
# I do not have anything set up for the console though, so that's still broken for now.
mkdir -p "${basedir}"/kali-${architecture}/usr/local/bin
cat << 'EOF' > "${basedir}"/kali-${architecture}/usr/local/bin/xrandrscript.sh
#!/usr/bin/env bash

resolution=$(xdpyinfo | awk '/dimensions:/ { print $2; exit }')

if [[ "$resolution" == "1366x768" ]]; then
    xrandr --newmode "1360x768_60.00"   84.75  1360 1432 1568 1776  768 771 781 798 -hsync +vsync
    xrandr --addmode HDMI-1 1360x768_60.00
    xrandr --output HDMI-1 --mode  1360x768_60.00
fi
EOF
chmod 755 "${basedir}"/kali-${architecture}/usr/local/bin/xrandrscript.sh

mkdir -p "${basedir}"/kali-${architecture}/usr/share/lightdm/lightdm.conf.d/
cat << EOF > "${basedir}"/kali-${architecture}/usr/share/lightdm/lightdm.conf.d/60-xrandrscript.conf
[SeatDefaults]
display-setup-script=/usr/local/bin/xrandrscript.sh
session-setup-script=/usr/local/bin/xrandrscript.sh
EOF

# Make sure we can login as root on the serial console.
# Mainline gives us a ttyAML0 which doesn't exist in there.

cat << EOF >> "${basedir}"/kali-${architecture}/etc/securetty

# Amlogic serial console
ttyAML0
ttyAML1
ttyAML2
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section.
git clone --depth 1 -b linux-4.18.y https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git "${basedir}"/kali-${architecture}/usr/src/kernel
cd "${basedir}"/kali-${architecture}/usr/src/kernel
touch .scmversion
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
# We need to apply a "few" various fixes...  this is gonna take a while.
#git apply "${basedir}"/../patches/mainline/0001-clk-meson-gxbb-set-fclk_div2-as-CLK_IS_CRITICAL.patch
git apply "${basedir}"/../patches/mainline/0002-ARM64-dts-meson-gxbb-nanopi-k2-Add-HDMI-CEC-and-CVBS.patch
git apply "${basedir}"/../patches/mainline/0003-drm-meson-Make-DMT-timings-parameters-and-pixel-cloc.patch
git apply "${basedir}"/../patches/mainline/0004-ARM64-defconfig-enable-CEC-support.patch
git apply "${basedir}"/../patches/mainline/0005-clk-meson-switch-gxbb-cts-amclk-div-to-the-generic-d.patch
git apply "${basedir}"/../patches/mainline/0006-clk-meson-remove-unused-clk-audio-divider-driver.patch
git apply "${basedir}"/../patches/mainline/0007-ASoC-meson-add-meson-audio-core-driver.patch
git apply "${basedir}"/../patches/mainline/0008-ASoC-meson-add-register-definitions.patch
git apply "${basedir}"/../patches/mainline/0009-ASoC-meson-add-aiu-i2s-dma-support.patch
git apply "${basedir}"/../patches/mainline/0010-ASoC-meson-add-initial-i2s-dai-support.patch
git apply "${basedir}"/../patches/mainline/0011-ASoC-meson-add-aiu-spdif-dma-support.patch
git apply "${basedir}"/../patches/mainline/0012-ASoC-meson-add-initial-spdif-dai-support.patch
git apply "${basedir}"/../patches/mainline/0013-ARM64-defconfig-enable-audio-support-for-meson-SoCs-.patch
git apply "${basedir}"/../patches/mainline/0014-ARM64-dts-meson-gx-add-audio-controller-nodes.patch
git apply "${basedir}"/../patches/mainline/0015-snd-meson-activate-HDMI-audio-path.patch
git apply "${basedir}"/../patches/mainline/0016-drm-meson-select-dw-hdmi-i2s-audio-for-meson-hdmi.patch
git apply "${basedir}"/../patches/mainline/0017-ARM64-dts-meson-gx-add-sound-dai-cells-to-HDMI-node.patch
git apply "${basedir}"/../patches/mainline/0018-ARM64-dts-meson-activate-hdmi-audio-HDMI-enabled-boa.patch
git apply "${basedir}"/../patches/mainline/0019-drm-bridge-dw-hdmi-Use-AUTO-CTS-setup-mode-when-non-.patch
git apply "${basedir}"/../patches/mainline/0020-drm-meson-Call-drm_crtc_vblank_on-drm_crtc_vblank_of.patch
git apply "${basedir}"/../patches/mainline/0021-media-platform-meson-ao-cec-make-busy-TX-warning-sil.patch
git apply "${basedir}"/../patches/mainline/90dc377aa5ed708a38a010e6861b468cd9373f4f.patch
# Nick a couple from Armbian
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/mainline/general-increasing_DMA_block_memory_allocation_to_2048.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/mainline/board-odroidc2-enable-scpi-dvfs.patch
# And now the two wifi related so we can do things.
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/kali-wifi-injection-4.16.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
# Now copy in the config file and then build this sucker
cp "${basedir}"/../kernel-configs/odroidc2-mainline.config .config
cp .config "${basedir}"/kali-${architecture}/usr/src/odroidc2-mainline.config
cd "${basedir}"/kali-${architecture}/usr/src/kernel/
rm -rf "${basedir}"/kali-${architecture}/usr/src/kernel/.git
make -j $(grep -c processor /proc/cpuinfo)
make modules_install INSTALL_MOD_PATH="${basedir}"/kali-${architecture}
cp arch/arm64/boot/Image "${basedir}"/kali-${architecture}/boot/
cp arch/arm64/boot/dts/amlogic/meson-gxbb-odroidc2.dtb "${basedir}"/kali-${architecture}/boot/
cd "${basedir}"/kali-${architecture}/usr/src/kernel
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper
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

cd "${basedir}"

# rpi-wiggle
mkdir -p "${basedir}"/kali-${architecture}/root/scripts
wget https://raw.github.com/steev/rpiwiggle/master/rpi-wiggle -O "${basedir}"/kali-${architecture}/root/scripts/rpi-wiggle.sh
chmod 755 "${basedir}"/kali-${architecture}/root/scripts/rpi-wiggle.sh

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config

# U-boot sees the emmc as mmc1, sdcard as mmc0
# Kernel sees the emmc as mmcblk0, sdcard as mmcblk1.
# Because of this, we can't pass root=/dev/mmcblkX because it changes based on people using
# emmc/sdcard, so we try to get fancy and have U-Boot spit out the part uuid for the root partition.
# All the reading I've done says that the partuuid never changes, however, in my testing with the sed line
# lower in the script (commented out presently) it was changing, when I would image to an actual sdcard or
# emmc.  So this way we should be able to have u-boot replace it with whatever it sees, and that should do
# the right thing.
cat << 'EOF' > "${basedir}"/kali-${architecture}/boot/boot.cmd
setenv loadaddr "0x20000000"
setenv dtb_loadaddr "0x01000000"
setenv initrd_high "0xffffffff"
setenv fdt_high "0xffffffff"
setenv kernel_filename Image
setenv fdt_filename meson-gxbb-odroidc2.dtb
if test "${devtype}" = "mmc"; then part uuid ${devtype} ${devnum}:2 rootpartuuid; fi
setenv bootargs "root=PARTUUID=${rootpartuuid} rootfstype=ext3 rootwait rw net.ifnames=0 ipv6.disable=1"
# Without an initramfs
setenv bootcmd "load ${devtype} ${devnum}:${partition} '${loadaddr}' '${kernel_filename}'; load ${devtype} ${devnum}:${partition} '${dtb_loadaddr}' '${fdt_filename}'; booti '${loadaddr}' - '${dtb_loadaddr}'"
# With an initramfs
# NOTE: EXPECTS THE INITRAMFS FILENAME TO BE "initramfs.gz"
# setenv bootcmd "load ${devtype} ${devnum}:${partition} '${loadaddr}' '${kernel_filename}'; load ${devtype} ${devnum}:${partition} '${dtb_loadaddr}' '${fdt_filename}'; load ${devtype} ${devnum}:${partition} ${ramdisk_addr_r} initramfs.gz; booti '${loadaddr}' ${ramdisk_addr_r}:${filesize} '${dtb_loadaddr}'"
boot
EOF

# Some maths here... it's not magic, we just want the block size a certain way
# so that partitions line up in a way that's more optimal.
RAW_SIZE_MB=${size}
BLOCK_SIZE=1024
let RAW_SIZE=(${RAW_SIZE_MB}*1000*1000)/${BLOCK_SIZE}

# Create the disk and partition it
echo "Creating image file ${imagename}.img"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=${BLOCK_SIZE} count=0 seek=${RAW_SIZE}
parted ${imagename}.img --script -- mklabel msdos
parted ${imagename}.img --script -- mkpart primary ext3 4096s 264191s
parted ${imagename}.img --script -- mkpart primary ext3 264192s 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.ext3 -L boot ${bootp}
mkfs.ext3 -L rootfs ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root
mkdir -p "${basedir}"/root/boot
mount ${bootp} "${basedir}"/root/boot

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

# u-boot sees the sdcard as mmc0, emmc as mmc1
# kernel sees the sdcard as mmcblk1, emmc as mmc0
# So we need to use the PARTUUID for the rootfs partition in order to boot, since
# we can't pass /dev/mmcblkXp2 for the rootdevice.  If an initramfs is used, this could probably be skipped
# by using the LABEL or UUID, but either way, here we go.
#sed -i -e "s/root=\/dev\/mmcblk0p2/root=PARTUUID=$(blkid -s PARTUUID -o value ${rootp})/g" "${basedir}"/kali-${architecture}/boot/boot.cmd

# Let's cat the output of the file so we can make sure it's correct.
cat "${basedir}"/kali-${architecture}/boot/boot.cmd
# And NOW we can actually make it the boot.scr that is needed.
mkimage -A arm -T script -C none -d "${basedir}"/kali-${architecture}/boot/boot.cmd "${basedir}"/kali-${architecture}/boot/boot.scr

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${basedir}"/kali-${architecture}/ "${basedir}"/root/

# Unmount partitions
# Sync before unmounting to ensure everything is written
sync
umount -l ${bootp}
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

mkdir -p "${basedir}"/bootloader
cd "${basedir}"/bootloader
git clone https://github.com/afaerber/meson-tools --depth 1
git clone git://git.denx.de/u-boot --depth 1
git clone https://github.com/hardkernel/u-boot -b odroidc2-v2015.01 u-boot-hk --depth 1

# First things first, let's build the meson-tools, of which, we only really need amlbootsig
cd "${basedir}"/bootloader/meson-tools/
make
# Now we need to build fip_create
cd "${basedir}"/bootloader/u-boot-hk/tools/fip_create
HOSTCC=cc HOSTLD=ld make

cd "${basedir}"/bootloader/u-boot/
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
cd "${basedir}"/bootloader/
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
echo "Cleaning up the temporary build files..."
rm -rf "${basedir}"
