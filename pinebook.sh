#!/bin/bash
set -e

# This image is for the Pinebook.

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
imagename=${3:-kali-linux-$1-pinebook}
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
basedir=${current_dir}/pinebook-"$1"
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
base="apt-transport-https apt-utils arm-trusted-firmware bash-completion console-setup dialog dkms e2fsprogs ifupdown initramfs-tools inxi iw linux-headers-arm64 linux-image-arm64 man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux u-boot-sunxi u-boot-menu unrar usbutils vim wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-input-evdev xserver-xorg-input-synaptics xfonts-terminus xinput"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware kali-linux-core libnss-systemd libssl-dev triggerhappy"

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

# Third stage
cat << EOF >  ${work_dir}/third-stage
#!/bin/bash -e
export DEBIAN_FRONTEND=noninteractive
export RUNLEVEL=1
ln -sf /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update

apt-get -y install git binutils ca-certificates console-common cryptsetup-bin initramfs-tools less locales nano u-boot-tools

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

apt-get -y --allow-change-held-packages autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/

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

# We replace the u-boot menu defaults here so we can make sure the build system doesn't poison it.
# We use _EOF_ so that the third-stage script doesn't end prematurely.
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=ext3 net.ifnames=0"
U_BOOT_MENU_LABEL="Kali Linux"
_EOF_

# Install touchpad config file
install -m644 /bsp/xorg/50-pine64-pinebook.touchpad.conf /etc/X11/xorg.conf.d/

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Add wifi firmware and driver, and attempt to build, so we don't need to build on
# first boot, which causes issues if people log in too soon...
# Pull in the wifi and bluetooth firmware from anarsoul's git repository.
git clone https://github.com/anarsoul/rtl8723bt-firmware
cd rtl8723bt-firmware
cp -a rtl_bt /lib/firmware/

# Need to package up the wifi driver (it's a Realtek 8723cs, with the usual
# Realtek driver quality) still, so for now, we clone it and then build it
# inside the chroot.
cd /usr/src/
git clone https://github.com/icenowy/rtl8723cs rtl8723cs-2020.02.07
cat << __EOF__ > /usr/src/rtl8723cs-2020.02.07/dkms.conf
PACKAGE_NAME="rtl8723cs"
PACKAGE_VERSION="2020.02.27"

AUTOINSTALL="yes"

CLEAN[0]="make clean"

MAKE[0]="'make' -j4 ARCH=arm64 KVER=\${kernelver} KSRC=/lib/modules/\${kernelver}/build/"

BUILT_MODULE_NAME[0]="8723cs"

BUILT_MODULE_LOCATION[0]=""

DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
__EOF__

cd rtl8723cs-2020.02.07
dkms install rtl8723cs/2020.02.27 -k $(ls /lib/modules/)

rm -f /usr/sbin/policy-rc.d
unlink /usr/sbin/invoke-rc.d
EOF

# Run third stage
chmod 755 ${work_dir}/third-stage
systemd-nspawn_exec /third-stage



cat << EOF > ${work_dir}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

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

# Set up some defaults for chromium, if the user ever installs it
mkdir -p ${work_dir}/etc/chromium/
cat << EOF > ${work_dir}/etc/chromium/default
#Options to pass to chromium
CHROMIUM_FLAGS="\
--disable-smooth-scrolling \
--disable-low-res-tiling \
--enable-low-end-device-mode \
--num-raster-threads=\$(nproc) \
--profiler-timing=0 \
--disable-composited-antialiasing \
"
EOF

cd ${current_dir}

# Calculate the space to create the image.
free_space=$((${free_space}*1024))
bootstart=$((${bootsize}*1024/1000*2*1024/2))
bootend=$((${bootstart}+1024))
rootsize=$(du -s --block-size KiB ${work_dir} --exclude boot | cut -f1)
rootsize=$((${free_space}+${rootsize//KiB/ }/1000*2*1024/2))
raw_size=$((${free_space}+${rootsize}+${bootstart}))

echo "Creating image file for ${imagename}.img"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=1KiB count=0 seek=${raw_size} && sync
parted ${basedir}/${imagename}.img --script -- mklabel msdos
parted ${basedir}/${imagename}.img --script -- mkpart primary ext3 32MiB 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p1

# Create file systems
mkfs.ext3 -L ROOTFS -O ^64bit,^flex_bg,^metadata_csum ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > ${work_dir}/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot.
# We do this down here because we don't know the UUID until after the image is created.
sed -i -e "0,/root=.*/s//root=UUID=$(blkid -s UUID -o value ${rootp}) rootfstype=ext3 console=ttyS0,115200 console=tty1 consoleblank=0 rw quiet rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf
# And we remove the "Debian GNU/Linux because we're Kali"
sed -i -e "s/Debian GNU\/Linux/Kali Linux/g" ${work_dir}/boot/extlinux/extlinux.conf

# And echo it so we can make sure it's correct...
cat ${work_dir}/boot/extlinux/extlinux.conf

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${basedir}/root/

# Do some wiggle work because we need to prep the u-boot bits for writing to the
# sdcard.
# Somewhat adapted from the u-boot-install-sunxi64 script

cd ${current_dir}
mkdir -p u-boot-itb
cd u-boot-itb
cp "${basedir}"/root/usr/lib/arm-trusted-firmware/sun50i_a64/bl31.bin .
cp "${basedir}"/root/usr/lib/u-boot/pinebook/* .
BL31=bl31.bin "${basedir}"/root/usr/bin/mksunxi_fit_atf *.dtb > u-boot.its
mkimage -f u-boot.its u-boot.itb

dd conv=fsync,notrunc if=sunxi-spl.bin of=${loopdevice} bs=8k seek=1
dd conv=notrunc if=u-boot.itb of=${loopdevice} bs=8k seek=5

# Unmount partitions
sync
umount ${rootp}

kpartx -dv ${loopdevice}
losetup -d ${loopdevice}


# Don't pixz on 32bit, there isn't enough memory to compress the images.
if [ $(arch) == 'x86_64' ]; then
  echo "Compressing ${imagename}.img"
  cd ${current_dir}
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
echo "Removing temporary build files"
rm -rf "${basedir}"