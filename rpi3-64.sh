#!/bin/bash
set -e

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
imagename=${3:-kali-linux-$1-rpi3-nexmon-64}
# Suite to use, valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
suite=${suite:-"kali-rolling"}
# Free space rootfs in MiB
free_space="300"
# /boot partition in MiB
bootsize="128"
# If you have your own preferred mirrors, set them here.
mirror="http://http.kali.org/kali"
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
basedir=${current_dir}/rpi3-nexmon-64-"$1"
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
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xserver-xorg-input-evdev xserver-xorg-input-synaptics"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware i2c-tools kali-linux-core libnss-systemd libssl-dev python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus triggerhappy"

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

# Third stage
cat << EOF >  ${work_dir}/third-stage
#!/bin/bash -e
export DEBIAN_FRONTEND=noninteractive
export RUNLEVEL=1
ln -sf /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update

apt-get -y install binutils ca-certificates cmake console-common git initramfs-tools less locales nano u-boot-tools

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

apt-get install -y \$aptops ${packages} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${packages} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get install -y \$aptops ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
# We want systemd-timesyncd not sntp which gets pulled in by something in kali-linux-default
apt-get install -y \$aptops --autoremove systemd-timesyncd

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/
cp -p /bsp/services/rpi/*.service /etc//systemd/system/

# Scripts for monitor mode
install -m755 /bsp/scripts/monstart /usr/bin/
install -m755 /bsp/scripts/monstop /usr/bin/

# Resize rootfs script
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

# Add rpi userland to the path (e.g. vcgencmd) 
install -m644 /bsp/configs/raspi-userland.conf /etc/ld.so.conf.d/
install -m644 /bsp/configs/vc.sh /etc/profile.d/vc.sh
install -m644 /bsp/udev/99-vchiq-permissions.rules /etc/udev/rules.d/

# Bluetooth enabling
install -m644 /bsp/bluetooth/rpi/99-com.rules /etc/udev/rules.d/
install -m644 /bsp/bluetooth/rpi/hciuart.service /etc/systemd/system/
install -m644 /bsp/bluetooth/rpi/btuart /usr/bin/

# Copy in the bluetooth firmware
install -m644 /bsp/firmware/rpi/BCM43430A1.hcd -D /lib/firmware/brcm/BCM43430A1.hcd

# Re4son's rpi-tft configurator
wget -q ${githubraw}/Re4son/RPi-Tweaks/master/kalipi-tft-config/kalipi-tft-config -O /usr/bin/kalipi-tft-config
chmod 755 /usr/bin/kalipi-tft-config

# Install the kernel packages
echo "deb http://http.re4son-kernel.com/re4son kali-pi main" > /etc/apt/sources.list.d/re4son.list
wget -qO /etc/apt/trusted.gpg.d/re4son-repo-key.asc https://re4son-kernel.com/keys/http/archive-key.asc
apt-get update
apt-get install --yes --allow-change-held-packages -o dpkg::options::=--force-confnew kalipi-kernel kalipi-bootloader kalipi-re4son-firmware kalipi-kernel-headers

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot
systemctl enable smi-hack

# Resize filesystem on first boot
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Enable hciuart for bluetooth device
systemctl enable hciuart

# Enable copying of user wpa_supplicant.conf file
systemctl enable copy-user-wpasupplicant

# Enable... enabling ssh by putting ssh or ssh.txt file in /boot
systemctl enable enable-ssh

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Attempt to build the raspi userland
cd /root
git clone https://github.com/raspberrypi/userland
cd userland
./buildme --aarch64
cd
rm -rf /root/userland

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/lib/systemd/system/networking.service"


rm -f /usr/sbin/policy-rc.d
unlink /usr/sbin/invoke-rc.d
EOF

# Run third stage
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
#deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# Create cmdline.txt file
cat << EOF > ${work_dir}/boot/cmdline.txt
dwc_otg.fiq_fix_enable=2 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext3 rootwait rootflags=noload net.ifnames=0
EOF

# systemd doesn't seem to be generating the fstab properly for some people, so
# let's create one.
cat << EOF > ${work_dir}/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext3    defaults,noatime  0       1
EOF

# Copy a default config, with everything commented out so people find it when
# they go to add something when they are following instructions on a website.
cp ./bsp/firmware/rpi/config.txt ${work_dir}/boot/config.txt
# Remove repeat conditional filters [all] in config.txt
sed -i "59,66d" ${work_dir}/boot/config.txt

# To boot 64bit, these lines *have* to be in config.txt
cat << EOF >> ${work_dir}/boot/config.txt

[pi2]
# Pi2 is 64bit only on v1.2+
# 64bit kernel for Raspberry Pi 2 is called kernel8 (armv8a)
kernel=kernel8-alt.img
[pi3]
# 64bit kernel for Raspberry Pi 3 is called kernel8 (armv8a)
kernel=kernel8-alt.img
[pi4]
# Enable DRM VC4 V3D driver on top of the dispmanx display stack
#dtoverlay=vc4-fkms-v3d
#max_framebuffers=2
# 64bit kernel for Raspberry Pi 4 is called kernel8l (armv8a)
kernel=kernel8l-alt.img
[all]
#dtoverlay=vc4-fkms-v3d
# Tell firmware to go 64bit mode.
arm_64bit=1
EOF



cd ${current_dir}

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
parted "${basedir}"/${imagename}.img --script -- mkpart primary fat32 1MiB ${bootstart}KiB
parted "${basedir}"/${imagename}.img --script -- mkpart primary ext3 ${bootend}KiB 100%

# Set the partition variables
bootp="$(losetup -o 1MiB --sizelimit ${bootstart}KiB -f --show ${basedir}/${imagename}.img)"
rootp="$(losetup -o ${bootend}KiB --sizelimit ${raw_size}KiB -f --show ${basedir}/${imagename}.img)"

# Create file systems
mkfs.vfat -n BOOT -F 32 -v ${bootp}
mkfs.ext3 -L ROOTFS -O ^64bit,^flex_bg,^metadata_csum ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p ${basedir}/root/
mount ${rootp} ${basedir}/root
mkdir -p ${basedir}/root/boot
mount ${bootp} ${basedir}/root/boot

echo "Rsyncing rootfs into image file"
rsync -HPavz -q --exclude boot ${work_dir}/ ${basedir}/root/
rsync -rtx -q ${work_dir}/boot ${basedir}/root
sync

# Make sure to enable ssh on the device by default
touch "${basedir}"/root/boot/ssh

sync
# Unmount filesystems
umount -l ${bootp}
umount -l ${rootp}

# Remove loop devices
losetup -d ${bootp}
losetup -d ${rootp}

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
echo "Cleaning up the temporary build files..."
rm -rf "${basedir}"
