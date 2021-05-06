#!/bin/bash
set -e

# This is Kali Linux ARM image for Raspberry Pi Zero W (nexmon) (Minimal)
# More information: https://www.kali.org/docs/arm/raspberry-pi-zero-w/

# Uncomment to activate debug
# debug=true

if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"armel"}
# Generate a random machine name to be used
machine=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c16 ; echo)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end
imagename=${3:-kali-linux-$1-rpi0-w-minimal}
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
basedir=${current_dir}/rpi0-w-"$1"-minimal
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
base="apt-transport-https apt-utils console-setup e2fsprogs ifupdown initramfs-tools iw man-db mlocate netcat-traditional net-tools parted psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree firmware-linux firmware-realtek firmware-atheros firmware-libertas kali-defaults network-manager snmpd snmp sudo tftp"
#desktop="kali-desktop-xfce fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev xserver-xorg-input-evdev xserver-xorg-input-synaptics"
## Kali Tools (Make it light as possible)
tools="kali-tools-top10"
# OS services
services="apache2 atftpd openssh-server openvpn tightvncserver"
# Any extra packages
extras="alsa-utils bc bison bluez bluez-firmware i2c-tools libnss-systemd libssl-dev lua5.1 python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus triggerhappy wpasupplicant"

packages="${arm} ${base} ${services}"

# Check to ensure that the architecture is set to ARMEL since the RPi is the
# only board that is armel
if [[ ${architecture} != "armel" ]] ; then
    echo "The Raspberry Pi cannot run the Debian armhf binaries"
    exit 0
fi

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

eatmydata apt-get -y install binutils ca-certificates console-common git less locales nano initramfs-tools u-boot-tools

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
eatmydata apt-get autoremove -y --allow-change-held-packages --purge

# Linux console/keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
install -m644 /bsp/services/all/*.service /etc/systemd/system/
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

# Re4son's rpi-tft configurator
wget -q ${githubraw}/Re4son/RPi-Tweaks/master/kalipi-tft-config/kalipi-tft-config -O /usr/bin/kalipi-tft-config
chmod 755 /usr/bin/kalipi-tft-config

# Script mode wlan monitor START/STOP
install -m755 /bsp/scripts/monstart /usr/bin/
install -m755 /bsp/scripts/monstop /usr/bin/

# Install the kernel packages
echo "deb http://http.re4son-kernel.com/re4son kali-pi main" > /etc/apt/sources.list.d/re4son.list
wget -qO /etc/apt/trusted.gpg.d/re4son-repo-key.asc https://re4son-kernel.com/keys/http/archive-key.asc
eatmydata apt-get update
eatmydata apt-get -y install \$aptops kalipi-kernel kalipi-bootloader kalipi-re4son-firmware kalipi-kernel-headers

# Enable bluetooth
# Copy in the bluetooth firmware
install -m644 /bsp/firmware/rpi/BCM43430A1.hcd -D /lib/firmware/brcm/BCM43430A1.hcd
# Copy rule and service
install -m644 /bsp/bluetooth/rpi/99-com.rules /etc/udev/rules.d/
install -m644 /bsp/bluetooth/rpi/hciuart.service /etc/systemd/system/

# Enable hciuart for bluetooth device
install -m755 /bsp/bluetooth/rpi/btuart /usr/bin/
systemctl enable hciuart

# Regenerate the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot
systemctl enable smi-hack

# Resize FS on first run (hopefully)
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Enable sshd
systemctl enable ssh

# Enable copying of user wpa_supplicant.conf file
systemctl enable copy-user-wpasupplicant

# We don't use network-manager on the 0w so we need to make sure wpa_supplicant is started
systemctl enable wpa_supplicant

# Enable sshd by putting ssh or ssh.txt file in /boot
systemctl enable enable-ssh

# Install pi-bluetooth deb package from re4son
dpkg --force-all -i /bsp/bluetooth/rpi/pi-bluetooth+re4son_2.2_all.deb

# Turn off kernel dmesg showing up in console since rpi0 only uses console
echo "#!/bin/sh -e" > /etc/rc.local
echo "#" >> /etc/rc.local
echo "# rc.local" >> /etc/rc.local
echo "#" >> /etc/rc.local
echo "# This script is executed at the end of each multiuser runlevel." >> /etc/rc.local
echo "# Make sure that the script will "exit 0" on success or any other" >> /etc/rc.local
echo "# value on error." >> /etc/rc.local
echo "#" >> /etc/rc.local
echo "# In order to enable or disable this script just change the execution" >> /etc/rc.local
echo "# bits." >> /etc/rc.local
echo "dmesg -D" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod +x /etc/rc.local

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc


# Set a REGDOMAIN. This needs to be done or wireless may not work correctly
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

# Whitelist /dev/ttyGS0 so that users can login over the gadget serial device if they enable it
# https://github.com/offensive-security/kali-arm-build-scripts/issues/151
echo "ttyGS0" >> /etc/securetty

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

# Define sources.list
cat << EOF > "${work_dir}"/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

# Create cmdline.txt file
cat << EOF > "${work_dir}"/boot/cmdline.txt
dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=$fstype elevator=deadline fsck.repair=yes rootwait
EOF

# systemd doesn't seem to be generating the fstab properly for some people, so
# let's create one
cat << EOF > "${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               $fstype    defaults,noatime  0       1
EOF

# Copy a default config, with everything commented out so people find it when
# they go to add something when they are following instructions on a website
cp ./bsp/firmware/rpi/config.txt ${work_dir}/boot/config.txt
# Remove repeat conditional filters [all] in config.txt
sed -i "59,66d" ${work_dir}/boot/config.txt

cd "${basedir}"

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
parted -s ${current_dir}/${imagename}.img mkpart primary fat32 1MiB ${bootsize}MiB
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype ${bootsize}MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
bootp="${loopdevice}p1"
rootp="${loopdevice}p2"

# Create file systems
mkfs.vfat -n BOOT -F 32 -v ${bootp}
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
mkdir -p "${basedir}"/root/boot
mount ${bootp} ${basedir}/root/boot

# We do this down here to get rid of the build system's resolv.conf after running through the build
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

echo "Rsyncing rootfs into image file"
rsync -HPavz -q --exclude boot "${work_dir}"/boot "${basedir}"/root/
rsync -rtx -q ${work_dir}/boot ${basedir}/root

# Start to unmount partition(s)
sync; sync
# sleep for 10 seconds, to let the cache settle after sync
sleep 10
# Unmount filesystem
umount -l "${bootp}"
umount -l "${rootp}"

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
