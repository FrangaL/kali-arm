#!/bin/bash
set -e

# This is Kali Linux ARM image for NanoPi NEO Plus2
# More information: https://www.kali.org/docs/arm/nanopi-neo-plus2/

# Uncomment to activate debug
# debug=true

if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"arm64"}
# Generate a random machine name to be used
machine=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c16 ; echo)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end
imagename=${3:-kali-linux-$1-nanopi-neo-plus2}
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
basedir=${current_dir}/nanopineoplus2-"$1"
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
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree"
#desktop="kali-desktop-xfce kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xfonts-terminus xinput"
# Kali Tools
tools="kali-linux-default"
# OS services
services="apache2 atftpd haveged"
# Any extra packages
extras="alsa-utils bc bison bluez bluez-firmware kali-linux-core libssl-dev triggerhappy"

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

mkdir -p kali-${architecture}/etc/network
cat << EOF > kali-${architecture}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# This prevents NetworkManager from attempting to use this
# device to connect to wifi, since NM doesn't show which device is which
# Unfortunately, it still SHOWS the device, just that it's not managed
iface p2p0 inet manual
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

# Eventually this should become a systemd service, but for now, we use the same
# init.d file that they provide and we let systemd handle the conversion
mkdir -p ${work_dir}/etc/init.d/
cat << 'EOF' > ${work_dir}/etc/init.d/brcm_patchram_plus
#!/bin/bash

### BEGIN INIT INFO
# Provides:             brcm_patchram_plus
# Required-Start:       $remote_fs $syslog
# Required-Stop:        $remote_fs $syslog
# Default-Start:        2 3 4 5
# Default-Stop:
# Short-Description:    brcm_patchram_plus
### END INIT INFO

function reset_bt()
{
    BTWAKE=/proc/bluetooth/sleep/btwake
    if [ -f ${BTWAKE} ]; then
        echo 0 > ${BTWAKE}
    fi
    index=`rfkill list | grep $1 | cut -f 1 -d":"`
    if [[ -n ${index} ]]; then
        rfkill block ${index}
        sleep 1
        rfkill unblock ${index}
        sleep 1
    fi
}

case "$1" in
    start|"")
        index=`rfkill list | grep "sunxi-bt" | cut -f 1 -d":"`
        brcm_try_log=/var/log/brcm/brcm_try.log
        brcm_log=/var/log/brcm/brcm.log
        brcm_err_log=/var/log/brcm/brcm_err.log
        if [ -d /sys/class/rfkill/rfkill${index} ]; then
            rm -rf ${brcm_log}
            reset_bt "sunxi-bt"
            [ -d /var/log/brcm ] || mkdir -p /var/log/brcm
            chmod 0660 /sys/class/rfkill/rfkill${index}/state
            chmod 0660 /sys/class/rfkill/rfkill${index}/type
            chgrp dialout /sys/class/rfkill/rfkill${index}/state
            chgrp dialout /sys/class/rfkill/rfkill${index}/type
            MACADDRESS=`md5sum /sys/class/sunxi_info/sys_info | cut -b 1-12 | sed -r ':1;s/(.*[^:])([^:]{2})/\1:\2/;t1'`
            let TIMEOUT=150
            while [ ${TIMEOUT} -gt 0 ]; do
                killall -9 /bin/brcm_patchram_plus
                /bin/brcm_patchram_plus -d --patchram /lib/firmware/ap6212/ --enable_hci --bd_addr ${MACADDRESS} --no2bytes --tosleep 5000 /dev/ttyS3 >${brcm_log} 2>&1 &
                sleep 30
                TIMEOUT=$((TIMEOUT-30))
                cur_time=`date "+%H-%M-%S"`
                if grep "Done setting line discpline" ${brcm_log}; then
                    echo "${cur_time}: bt firmware download ok(${TIMEOUT})" >> ${brcm_try_log}
                    if ! grep "fail" ${brcm_try_log}; then
                        reset_bt "hci0"
                        hciconfig hci0 up
                        hciconfig >> ${brcm_try_log}
                        #reboot
                    fi
                    break
                else
                    echo "${cur_time}: bt firmware download fail(${TIMEOUT})" >> ${brcm_try_log}
                    cp ${brcm_log} ${brcm_err_log}
                    reset_bt "sunxi-bt"
                fi
            done
        fi
        ;;

    stop)
    kill `ps --no-headers -C brcm_patchram_plus -o pid`
        ;;
    *)
        echo "Usage: brcm_patchram_plus start|stop" >&2
        exit 3
        ;;
esac
EOF
chmod 755 "${work_dir}"/etc/init.d/brcm_patchram_plus
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

# Required to kick the bluetooth chip
install -m755 /bsp/firmware/veyron/brcm_patchram_plus /bin/brcm_patchram_plus

# Regenerate the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot
systemctl enable smi-hack

# Resize FS on first run (hopefully)
systemctl enable rpiwiggle

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Enable sshd
systemctl enable ssh

# There's no graphical output on this device so
systemctl set-default multi-user

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc

# Enable bluetooth - we do this way because we haven't written a systemd service
# file for it yet
update-rc.d brcm_patchram_plus defaults

# Because they have it in the system image, lets go ahead and clone these as
# well
cd /home/kali/
git clone --depth 1 https://github.com/friendlyarm/WiringNP
git clone --depth 1 https://github.com/auto3000/RPi.GPIO_NP
chown -R kali:kali {WiringNP,RPi.GPIO_NP}
cd /

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/g' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/g' /etc/default/console-setup

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

cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Define sources.list
cat << EOF > "${work_dir}"/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section
git clone --depth 1 https://github.com/friendlyarm/linux -b sunxi-4.x.y ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
cp "${current_dir}"/kernel-configs/neoplus2.config ${work_dir}/usr/src/kernel/.config
cp "${current_dir}"/kernel-configs/neoplus2.config ${work_dir}/usr/src/
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/kali-wifi-injection-4.14.patch
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make -j $(grep -c processor /proc/cpuinfo)
make modules
make modules_install INSTALL_MOD_PATH=${work_dir}
cp arch/arm64/boot/Image ${work_dir}/boot
cp arch/arm64/boot/dts/allwinner/*.dtb ${work_dir}/boot/
mkdir -p ${work_dir}/boot/overlays/
cp arch/arm64/boot/dts/allwinner/overlays/*.dtb ${work_dir}/boot/overlays/
make mrproper
cd "${current_dir}"

# Copy over the firmware for the ap6212 wifi
# On the neo plus2 default install there are other firmware files installed for
# p2p and apsta but I can't find them publicly posted to friendlyarm's github
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon
mkdir -p ${work_dir}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${work_dir}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/config.txt

# The way the base system comes, the firmware seems to be a symlink into the
# ap6212 directory so let's do the same here
# NOTE: This means we can't install firmware-brcm80211 firmware package because
# the firmware will conflict, and based on testing the firmware in the package
# *will not* work with this device
mkdir -p ${work_dir}/lib/firmware/brcm
cd ${work_dir}/lib/firmware/brcm
ln -s /lib/firmware/ap6212/fw_bcm43438a1.bin brcmfmac43430a1-sdio.bin
ln -s /lib/firmware/ap6212/nvram_ap6212.txt brcmfmac43430a1-sdio.txt
ln -s /lib/firmware/ap6212/fw_bcm43438a0.bin brcmfmac43430-sdio.bin
ln -s /lib/firmware/ap6212/nvram.txt brcmfmac43430-sdio.txt
cd "${current_dir}"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${current_dir}"

cat << EOF > "${work_dir}"/boot/boot.cmd
# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr

setenv fsck.repair yes
setenv ramdisk rootfs.cpio.gz
setenv kernel Image

setenv env_addr 0x45000000
setenv kernel_addr 0x46000000
setenv ramdisk_addr 0x47000000
setenv dtb_addr 0x48000000
setenv fdtovaddr 0x49000000

fatload mmc 0 \${kernel_addr} \${kernel}
fatload mmc 0 \${ramdisk_addr} \${ramdisk}
if test \$board = nanopi-neo2-v1.1; then
    fatload mmc 0 \${dtb_addr} sun50i-h5-nanopi-neo2.dtb
else
    fatload mmc 0 \${dtb_addr} sun50i-h5-\${board}.dtb
fi
fdt addr \${dtb_addr}

# setup NEO2-V1.1 with gpio-dvfs overlay
if test \$board = nanopi-neo2-v1.1; then
        fatload mmc 0 \${fdtovaddr} overlays/sun50i-h5-gpio-dvfs-overlay.dtb
        fdt resize 8192
    fdt apply \${fdtovaddr}
fi

# setup MAC address
fdt set ethernet0 local-mac-address \${mac_node}

# setup boot_device
fdt set mmc\${boot_mmc} boot_device <1>

setenv fbcon map:0
setenv bootargs console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootfstype=$fstype rw rootwait fsck.repair=\${fsck.repair} panic=10 \${extra} fbcon=\${fbcon} ipv6.disable=1
#booti \${kernel_addr} \${ramdisk_addr}:500000 \${dtb_addr}
booti \${kernel_addr} - \${dtb_addr}
EOF
mkimage -C none -A arm -T script -d ${work_dir}/boot/boot.cmd ${work_dir}/boot/boot.scr

# rpi-wiggle
mkdir -p ${work_dir}/root/scripts
wget https://raw.github.com/steev/rpiwiggle/master/rpi-wiggle -O ${work_dir}/root/scripts/rpi-wiggle.sh
chmod 755 "${work_dir}"/root/scripts/rpi-wiggle.sh

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
parted -s ${current_dir}/${imagename}.img mkpart primary fat32 32MiB ${bootsize}MiB
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype ${bootsize}MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${current_dir}/${imagename}.img")
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.vfat -n BOOT ${bootp}
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
mount ${bootp} "${basedir}"/root/boot

# Create an fstab so that we don't mount / read-only
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/boot "${basedir}"/root/

# Start to unmount partition(s)
sync; sync
# sleep for 10 seconds, to let the cache settle after sync
sleep 10
# Unmount filesystem
umount -l "${bootp}"
umount -l "${rootp}"

kpartx -dv ${loopdevice}

cd "${basedir}"
git clone --depth 1 https://github.com/friendlyarm/u-boot.git
cd u-boot
git checkout sunxi-v2017.x
make nanopi_h5_defconfig
make

# Write bootloader to imagefile
dd if=spl/sunxi-spl.bin of=${loopdevice} bs=1024 seek=8
dd if=u-boot.itb of=${loopdevice} bs=1024 seek=40

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
