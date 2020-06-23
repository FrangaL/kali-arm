#!/bin/bash
set -e

# This image is for the Pinebook.

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/pinebook-pro-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-pinebook-pro}
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

arm="kali-linux-arm ntpdate"
base="apt-transport-https apt-utils bash-completion console-setup dialog dkms e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware kali-linux-core libnss-systemd libssl-dev triggerhappy"

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

# No built in ethernet, so don't add eth0 here otherwise the
# networking.service will fail to start, despite it not being an actual
# issue.
mkdir -p kali-${architecture}/etc/network/
cat << EOF > kali-${architecture}/etc/network/interfaces
auto lo
iface lo inet loopback
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

# Disable RESUME (suspend/resume is currently broken anyway!) which speeds up boot massively.
mkdir -p kali-${architecture}/etc/initramfs-tools/conf.d/
cat << EOF > kali-${architecture}/etc/initramfs-tools/conf.d/resume
RESUME=none
EOF

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
apt-get -y install git-core binutils ca-certificates cryptsetup-bin initramfs-tools u-boot-tools
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
apt-get --yes --allow-change-held-packages --autoremove install systemd-timesyncd || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew dist-upgrade
apt-get --yes --allow-change-held-packages -o dpkg::options::=--force-confnew autoremove

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
systemctl enable ssh

# And enable bluetooth
systemctl enable bluetooth

# Copy bashrc
cp  /etc/skel/.bashrc /root/.bashrc

cd /root
apt download ca-certificates
apt download libgdk-pixbuf2.0-0
apt download fontconfig

# Enable suspend2idle
sed -i s/"#SuspendState=mem standby freeze"/"SuspendState=freeze"/g /etc/systemd/sleep.conf

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

# Enable serial console
echo 'T1:12345:respawn:/sbin/agetty 115200 ttymxc0 vt100' >> \
    "${basedir}"/kali-${architecture}/etc/inittab

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
#deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

mkdir -p "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/
cp "${basedir}"/../bsp/xorg/50-pine64-pinebook-pro.touchpad.conf "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/

# Mesa needs to be updated for panfrost fixes, so force fbdev until it comes.
#cat << EOF > "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/50-force-fbdev.conf
#Section "Device"  
#  Identifier "myfb"
#  Driver "fbdev"
#  Option "fbdev" "/dev/fb0"
#EndSection
#EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

cd "${basedir}"

# Pull in the wifi and bluetooth firmware from manjaro's git repository.
git clone https://gitlab.manjaro.org/manjaro-arm/packages/community/ap6256-firmware.git
cd ap6256-firmware
mkdir brcm
cp BCM4345C5.hcd brcm/BCM.hcd
cp BCM4345C5.hcd brcm/BCM4345C5.hcd
cp nvram_ap6256.txt brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt
cp fw_bcm43456c5_ag.bin brcm/brcmfmac43456-sdio.bin
cp brcmfmac43456-sdio.clm_blob brcm/brcmfmac43456-sdio.clm_blob
mkdir -p "${basedir}"/kali-${architecture}/lib/firmware/brcm/
cp -a brcm/* "${basedir}"/kali-${architecture}/lib/firmware/brcm/
cd "${basedir}"

# Time to build the kernel
cd "${basedir}"/kali-${architecture}/usr/src
git clone https://gitlab.manjaro.org/tsys/linux-pinebook-pro.git --depth 1 linux
cd linux
touch .scmversion
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/pinebook-pro/0001-net-smsc95xx-Allow-mac-address-to-be-set-as-a-parame.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/pinebook-pro/0008-board-rockpi4-dts-upper-port-host.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/pinebook-pro/0008-rk-hwacc-drm.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/pinebook-pro/kali-wifi-injection.patch
cp "${basedir}"/../kernel-configs/pinebook-pro-5.7.config .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- oldconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="${basedir}"/kali-${architecture} modules_install
cp arch/arm64/boot/Image "${basedir}"/kali-${architecture}/boot
cp arch/arm64/boot/dts/rockchip/rk3399-pinebook-pro.dtb "${basedir}"/kali-${architecture}/boot
# clean up because otherwise we leave stuff around that causes external modules
# to fail to build.
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper
# And copy the config back in again (and copy it to /usr/src to keep a backup
# around)
cp "${basedir}"/../kernel-configs/pinebook-pro-5.7.config .config
cp "${basedir}"/../kernel-configs/pinebook-pro-5.7.config ../default-config
cd "${basedir}"

# Fix up the symlink for building external modules
# kernver is used to we don't need to keep track of what the current compiled
# version is
kernver=$(ls "${basedir}"/kali-${architecture}/lib/modules)
cd "${basedir}"/kali-${architecture}/lib/modules/${kernver}/
rm build
rm source
ln -s /usr/src/linux build
ln -s /usr/src/linux source
cd "${basedir}"

cat << '__EOF__' > "${basedir}"/kali-${architecture}/boot/boot.txt
# MAC address (use spaces instead of colons)
setenv macaddr da 19 c8 7a 6d f4

part uuid ${devtype} ${devnum}:${bootpart} uuid
setenv bootargs console=ttyS2,1500000 root=PARTUUID=${uuid} rw rootwait video=eDP-1:1920x1080@60
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
cd "${basedir}"/kali-${architecture}/boot
mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d boot.txt boot.scr
cd "${basedir}"

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config

# Enable brightness up/down and sleep hotkeys and attempt to improve
# touchpad performance
mkdir -p "${basedir}"/kali-${architecture}/etc/udev/hwdb.d/
cat << 'EOF' > "${basedir}"/kali-${architecture}/etc/udev/hwdb.d/10-usb-kbd.hwdb
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

# Alsa settings for the soundcard
mkdir -p "${basedir}"/kali-${architecture}/var/lib/alsa/
cp "${basedir}"/../bsp/audio/pinebook-pro/asound.state kali-${architecture}/var/lib/alsa/asound.state

echo "Creating image file for ${imagename}.img"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=1M count=${size}
parted ${imagename}.img --script -- mklabel msdos
parted ${imagename}.img --script -- mkpart primary ext3 32M 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p1

# Create file systems
mkfs.ext3 ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Create an fstab so that we don't mount / read-only.
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               ext3    errors=remount-ro 0       1" >> "${basedir}"/kali-${architecture}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${basedir}"/kali-${architecture}/ "${basedir}"/root/

# Nick the u-boot from Manjaro ARM to see if my compilation was somehow
# screwing things up.
cp "${basedir}"/../bsp/bootloader/pinebook-pro/idbloader.img "${basedir}"/../bsp/bootloader/pinebook-pro/trust.img "${basedir}"/../bsp/bootloader/pinebook-pro/uboot.img "${basedir}"/root/boot/
dd if="${basedir}"/../bsp/bootloader/pinebook-pro/idbloader.img of=${loopdevice} seek=64 conv=notrunc
dd if="${basedir}"/../bsp/bootloader/pinebook-pro/uboot.img of=${loopdevice} seek=16384 conv=notrunc
dd if="${basedir}"/../bsp/bootloader/pinebook-pro/trust.img of=${loopdevice} seek=24576 conv=notrunc


# Unmount partitions
sync
umount ${rootp}

kpartx -dv ${loopdevice}
losetup -d ${loopdevice}

# Don't pixz on 32bit, there isn't enough memory to compress the images.
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
echo "Compressing ${imagename}.img"
xz -z "${basedir}"/${imagename}.img
mv "${basedir}"/${imagename}.img.xz "${basedir}"/../${imagename}.img.xz
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Removing temporary build files"
rm -rf "${basedir}"
