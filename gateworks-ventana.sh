#!/bin/bash
set -e

# This is Kali Linux ARM image for Gateworks Ventana
# More information: https://www.kali.org/docs/arm/gateworks-ventana/

# Uncomment to activate debug
# debug=true

if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"armhf"}
# Generate a random machine name to be used
machine=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c16 ; echo)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end
imagename=${3:-kali-linux-$1-ventana}
# Suite to use, valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
suite=${suite:-"kali-rolling"}
# Free space rootfs in MiB
free_space="300"
# /boot partition in MiB
bootsize="128"
# Select compression, xz or none
compress="xz"
# Choose filesystem format to format (ext3 or ext4)
fstype="ext3"
# If you have your own preferred mirrors, set them here
mirror=${mirror:-"http://http.kali.org/kali"}
# GitLab URL for Kali repository
kaligit="https://gitlab.com/kalilinux"
# GitHub raw URL
githubraw="https://raw.githubusercontent.com"

# Checks script environment
# Check EUID=0 you can run any binary as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or have super user permissions" >&2
  echo "Use: sudo $0 ${1:-2.0} ${2:-kali}" >&2
  exit 1
fi

# Pass version number
if [[ $# -eq 0 ]] ; then
  echo "Please pass version number, e.g. $0 2021.1, and (if you want) a hostname, default is kali" >&2
  echo "Use: sudo $0 ${1:-2020.1} ${2:-kali}" >&2
  exit 1
fi

# Check exist bsp directory
if [ ! -e "bsp" ]; then
  echo "Error: missing bsp directory structure" >&2
  echo "Please clone the full repository ${kaligit}/build-scripts/kali-arm" >&2
  exit 255
fi

# Current directory
current_dir="$(pwd)"
# Base directory
basedir=${current_dir}/ventana-"$1"
# Working directory
work_dir="${basedir}/kali-${architecture}"

# Check directory build
if [ -e "${basedir}" ]; then
  echo "${basedir} directory exists, will not continue" >&2
  exit 1
elif [[ ${current_dir} =~ [[:space:]] ]]; then
  echo "The directory "\"${current_dir}"\" contains whitespace. Not supported." >&2
  exit 1
else
  echo "The basedir thinks it is: ${basedir}"
  mkdir -p "${basedir}"
fi

components="main,contrib,non-free"

# Packages build list
# Every ARM device has this
arm="kali-linux-arm ntpdate"
# Required for the board
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree u-boot-menu isc-dhcp-server"
# GUI
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xfonts-terminus xinput"
# Kali Tools
tools="kali-linux-default"
# OS services
services="apache2 atftpd can-utils i2c-tools"
# Any extra packages
extras="alsa-utils bc bison bluez bluez-firmware kali-linux-core libssl-dev triggerhappy libnss-systemd"

packages="${arm} ${base} ${services}"

# Load automatic proxy configuration
# You can turn off automatic settings by uncommenting apt_cacher=off
# apt_cacher=off
# By default the proxy settings are local, but you can define an external proxy
# proxy_url="http://external.intranet.local"
apt_cacher=${apt_cacher:-"$(lsof -i :3142 | cut -d ' ' -f3 | uniq | sed '/^\s*$/d')"}
if [ -n "$proxy_url" ]; then
  export http_proxy=$proxy_url
elif [ "$apt_cacher" = "apt-cacher-ng" ] ; then
  if [ -z "$proxy_url" ]; then
    proxy_url=${proxy_url:-"http://127.0.0.1:3142/"}
    export http_proxy=$proxy_url
  fi
fi

# Detect architecture
if [[ "${architecture}" == "arm64" ]]; then
  qemu_bin="/usr/bin/qemu-aarch64-static"
  lib_arch="aarch64-linux-gnu"
elif [[ "${architecture}" == "armhf" ]]; then
  qemu_bin="/usr/bin/qemu-arm-static"
  lib_arch="arm-linux-gnueabihf"
elif [[ "${architecture}" == "armel" ]]; then
  qemu_bin="/usr/bin/qemu-arm-static"
  lib_arch="arm-linux-gnueabi"
fi

# Execute initial debootstrap
# create the rootfs - not much to modify here, except maybe throw in some more packages if you want
eatmydata debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring,eatmydata \
  --components=${components} --arch ${architecture} ${suite} ${work_dir} http://http.kali.org/kali

# systemd-nspawn enviroment
systemd-nspawn_exec(){
  LANG=C systemd-nspawn -q --bind-ro ${qemu_bin} -M ${machine} -D ${work_dir} "$@"
}

# We need to manually extract eatmydata to use it for the second stage
for archive in ${work_dir}/var/cache/apt/archives/*eatmydata*.deb; do
  dpkg-deb --fsys-tarfile "$archive" > ${work_dir}/eatmydata
  tar -xkf ${work_dir}/eatmydata -C ${work_dir}
  rm -f ${work_dir}/eatmydata
done

# Prepare dpkg to use eatmydata
systemd-nspawn_exec dpkg-divert --divert /usr/bin/dpkg-eatmydata --rename --add /usr/bin/dpkg

cat > ${work_dir}/usr/bin/dpkg << EOF
#!/bin/sh
if [ -e /usr/lib/${lib_arch}/libeatmydata.so ]; then
    [ -n "\${LD_PRELOAD}" ] && LD_PRELOAD="\$LD_PRELOAD:"
    LD_PRELOAD="\$LD_PRELOAD\$so"
fi
for so in /usr/lib/${lib_arch}/libeatmydata.so; do
    [ -n "\$LD_PRELOAD" ] && LD_PRELOAD="\$LD_PRELOAD:"
    LD_PRELOAD="\$LD_PRELOAD\$so"
done
export LD_PRELOAD
exec "\$0-eatmydata" --force-unsafe-io "\$@"
EOF
chmod 755 "${work_dir}"/usr/bin/dpkg

# debootstrap second stage
systemd-nspawn_exec eatmydata /debootstrap/debootstrap --second-stage

# Define sources.list
cat << EOF > "${work_dir}"/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

echo "${hostname}" > ${work_dir}/etc/hostname

cat << EOF > "${work_dir}"/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

allow-hotplug usb0
iface usb0 inet static
    address 10.10.10.1
    netmask 255.255.255.0
    network 10.10.10.0
    broadcast 10.10.10.255
EOF

# Set hostname
echo "${hostname}" > ${work_dir}/etc/hostname

# So X doesn't complain, we add kali to hosts
cat << EOF > "${work_dir}"/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Network configs
# Disable IPv6
cat << EOF > "${work_dir}"/etc/modprobe.d/ipv6.conf
# Don't load ipv6 by default
alias net-pf-10 off
EOF

cat << EOF > "${work_dir}"/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# DNS server
cat << EOF > "${work_dir}"/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Copy directory bsp into build dir
cp -rp bsp "${work_dir}"

export MALLOC_CHECK_=0 # workaround for LP: #520465

# Enable the use of http proxy in third-stage in case it is enabled
if [ -n "$proxy_url" ]; then
  echo "Acquire::http { Proxy \"$proxy_url\" };" > ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

# Third stage
cat << EOF > "${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

eatmydata apt-get update

eatmydata apt-get -y install binutils ca-certificates console-common less locales cryptsetup-bin git initramfs-tools u-boot-tools

# Create kali user with kali password... but first, we need to manually make some groups because they don't yet exist..
# This mirrors what we have on a pre-installed VM, until the script works properly to allow end users to set up their own... user
# However we leave off floppy, because who a) still uses them, and b) attaches them to an SBC!?
# And since a lot of these have serial devices of some sort, dialout is added as well
# scanner, lpadmin and bluetooth have to be added manually because they don't
# yet exist in /etc/group at this point
groupadd -r -g 118 bluetooth
groupadd -r -g 113 lpadmin
groupadd -r -g 122 scanner
groupadd -g 1000 kali

useradd -m -u 1000 -g 1000 -G sudo,audio,bluetooth,cdrom,dialout,dip,lpadmin,netdev,plugdev,scanner,video,kali -s /bin/bash kali
echo "kali:kali" | chpasswd

aptops="--allow-change-held-packages -o dpkg::options::=--force-confnew -o Acquire::Retries=3"

# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice
eatmydata apt-get -y install \$aptops ${packages} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get -y install \$aptops ${packages} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get -y install \$aptops ${desktop} ${extras} ${tools} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get -y install \$aptops ${desktop} ${extras} ${tools} || eatmydata apt-get --yes --fix-broken install

# We want systemd-timesyncd not sntp which gets pulled in by something in kali-linux-default
eatmydata apt-get -y install \$aptops --autoremove systemd-timesyncd || eatmydata apt-get --yes --fix-broken install

eatmydata apt-get dist-upgrade -y \$aptops
eatmydata apt-get autoremove -y --allow-change-held-packages -o dpkg::options::=--force-confnew --purge

# Copy all services
install -m644 /bsp/services/all/*.service /etc/systemd/system/

# Regenerate the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot
systemctl enable smi-hack

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Enable sshd
systemctl enable ssh

# We replace the u-boot menu defaults here so we can make sure the build system doesn't poison it
# We use _EOF_ so that the third-stage script doesn't end prematurely
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=$fstype net.ifnames=0"
_EOF_

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/g' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/g' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

rm -f /usr/bin/dpkg
EOF

# Run third stage
chmod 755 "${work_dir}"/third-stage
systemd-nspawn_exec /third-stage

# Set up usb gadget mode before cleanup
cat << EOF > "${work_dir}"/etc/dhcp/dhcpd.conf
ddns-update-style none;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet 10.10.10.0 netmask 255.255.255.0 {
        range 10.10.10.10 10.10.10.20;
        option subnet-mask 255.255.255.0;
        option domain-name-servers 8.8.8.8;
        option routers 10.10.10.1;
        default-lease-time 600;
        max-lease-time 7200;
}
EOF

echo | sed -e '/^#/d ; /^ *$/d' | systemd-nspawn_exec << EOF
#Setup Serial Port
#echo 'g_cdc' >> /etc/modules
#echo '\n# USB Gadget Serial console port\nttyGS0' >> /etc/securetty
#systemctl enable getty@ttyGS0.service
#Setup Ethernet Port
echo 'g_ether' >> /etc/modules
sed -i 's/INTERFACESv4=""/INTERFACESv4="usb0"/g' /etc/default/isc-dhcp-server
systemctl enable isc-dhcp-server
EOF

# Clean up eatmydata
systemd-nspawn_exec dpkg-divert --remove --rename /usr/bin/dpkg

# Clean system
systemd-nspawn_exec << 'EOF'
rm -f /0
rm -rf /bsp
fc-cache -frs
rm -rf /tmp/*
rm -rf /etc/*-
rm -rf /hs_err*
rm -rf /userland
rm -rf /opt/vc/src
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/dpkg/*-old
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*.data-old
for logs in $(find /var/log -type f); do > $logs; done
history -c
EOF

# Disable the use of http proxy in case it is enabled
if [ -n "$proxy_url" ]; then
  unset http_proxy
  rm -rf ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

# Mirror & suite replacement
if [[ ! -z "${4}" || ! -z "${5}" ]]; then
  mirror=${4}
  suite=${5}
fi

# Enable the serial console
echo 'T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100' >> ${work_dir}/etc/inittab

# Define sources.list
cat << EOF > "${work_dir}"/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

cd "${current_dir}"

# Do the kernel stuff..
git clone --depth 1 https://github.com/gateworks/linux-imx6 --branch gateworks_4.20.7 ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel/
# Don't change the version because of our patches
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
patch -p1 < ${current_dir}/patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 < ${current_dir}/patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
cp "${current_dir}"/kernel-configs/gateworks_ventana-4.20.7.config .config
cp "${current_dir}"/kernel-configs/gateworks_ventana-4.20.7.config ${work_dir}/usr/src/gateworks_ventana-4.20.7.config
make -j $(grep -c processor /proc/cpuinfo)
make uImage LOADADDR=0x10008000
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm/boot/dts/imx6*-gw*.dtb ${work_dir}/boot/
cp arch/arm/boot/uImage ${work_dir}/boot/
make mrproper
cd "${current_dir}"

# Pull in imx6 smda/vpu firmware for vpu
mkdir -p ${work_dir}/lib/firmware/vpu
mkdir -p ${work_dir}/lib/firmware/imx/sdma
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6dl.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6dl.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu/v4l-coda960-imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6d.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6d.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/vpu_fw_imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/imx/sdma/sdma-imx6q.bin?raw=true' -O ${work_dir}/lib/firmware/imx/sdma/sdma-imx6q.bin

# Not using extlinux.conf just yet..
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
#sed -i -e 's/append.*/append root=\/dev\/mmcblk0p1 rootfstype=$fstype video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 console=ttymxc0,115200n8 console=tty1 consoleblank=0 rw rootwait/g' ${work_dir}/boot/extlinux/extlinux.conf
install -m644 ${current_dir}/bsp/bootloader/ventana/6x_bootscript-ventana.script ${work_dir}/boot/6x_bootscript-ventana.script
mkimage -A arm -T script -C none -d ${work_dir}/boot/6x_bootscript-ventana.script ${work_dir}/boot/6x_bootscript-ventana

cd "${current_dir}"

# Calculate the space to create the image
root_size=$(du -s -B1 ${work_dir} --exclude=${work_dir}/boot | cut -f1)
echo $root_size
root_extra=$((${root_size}/1024/1000*5*1024/5))
echo $root_extra
raw_size=$(($((${free_space}*1024))+${root_extra}+$((${bootsize}*1024))+4096))
echo $raw_size

# Create the disk and partition it
echo "Creating image file ${imagename}.img"
fallocate -l $(echo ${raw_size}Ki | numfmt --from=iec-i --to=si) ${current_dir}/${imagename}.img
echo "Partitioning ${imagename}.img"
parted -s ${current_dir}/${imagename}.img mklabel msdos
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype 1MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p1

# Create file systems
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# We do this down here to get rid of the build system's resolv.conf after running through the build
cat << EOF > "${work_dir}"/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root/
mount "${rootp}" "${basedir}"/root

# Create an fstab so that we don't mount / read-only
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/boot "${basedir}"/root/

#wget http://dev.gateworks.com/ventana/images/SPL -O "${basedir}"/root/usr/lib/u-boot/gateworks/SPL
#wget http://dev.gateworks.com/ventana/images/u-boot.img -O "${basedir}"/root/usr/lib/u-boot/gateworks/u-boot.img
#dd conv=fsync,notrunc if="${basedir}"/root/usr/lib/u-boot/gateworks/SPL of=${loopdevice} bs=1k seek=1
#dd conv=fsync,notrunc if="${basedir}"/root/usr/lib/u-boot/gateworks/u-boot.img of=${loopdevice} bs=1k seek=69

# Start to unmount partition(s)
sync; sync
# sleep for 10 seconds, to let the cache settle after sync
sleep 10
# Unmount filesystem
umount -l "${rootp}"

# We need an older cross compiler for compiling u-boot so check out the 4.7
# cross compiler
#git clone --depth 1 https://github.com/offensive-security/gcc-arm-linux-gnueabihf-4.7

#git clone --depth 1 https://github.com/Gateworks/u-boot-imx6.git
#cd "${basedir}"/u-boot-imx6
#make CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- gwventana_defconfig
#make CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-

#dd if=SPL of=${loopdevice} bs=1K seek=1
#dd if=u-boot.img of=${loopdevice} bs=1K seek=42

kpartx -dv ${loopdevice}

cd "${basedir}"

# Remove loop device
losetup -d "${loopdevice}"

# Limited use CPU function
limit_cpu (){
  rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) # Random name group
  cgcreate -g cpu:/cpulimit-${rand} # Name of group cpulimit
  cgset -r cpu.shares=800 cpulimit-${rand} # Max 1024
  cgset -r cpu.cfs_quota_us=80000 cpulimit-${rand} # Max 100000
  # Retry command
  local n=1; local max=5; local delay=2
  while true; do
    cgexec -g cpu:cpulimit-${rand} "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo -e "\e[31m Command failed. Attempt $n/$max \033[0m"
        sleep $delay;
      else
        echo "The command has failed after $n attempts."
        break
      fi
    }
  done
}

if [ $compress = xz ]; then
  if [ $(arch) == 'x86_64' ]; then
    echo "Compressing ${imagename}.img"
    [ $(nproc) \< 3 ] || cpu_cores=3 # cpu_cores = Number of cores to use
    limit_cpu pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p Nº cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  fi
else
  chmod 644 ${current_dir}/${imagename}.img
fi

# Clean up all the temporary build stuff and remove the directories
# Comment this out to keep things around if you want to see what may have gone wrong
echo "Clean up the build system"
rm -rf "${basedir}"
