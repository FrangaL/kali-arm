#!/bin/bash -e
# This is the Gateworks Newport (Cavium Octeon based) Kali ARM 64 bit build script - http://www.kali.org/get-kali
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"gateworks-newport"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"xfce"}

# Load common variables
include variables
# Checks script enviroment
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
# Copy directory bsp into build dir.
cp -rp bsp "${work_dir}"

# Third stage
cat <<EOF >"${work_dir}"/third-stage
#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken

eatmydata apt-get -y --purge autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/


# Copy script rpi-resizerootfs
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

# Enable rpi-resizerootfs first boot
systemctl enable rpi-resizerootfs

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# We replace the u-boot menu defaults here so we can make sure the build system doesn't poison it.
# We use _EOF_ so that the third-stage script doesn't end prematurely.
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=$fstype net.ifnames=0"
_EOF_

# Enable login over serial
echo "T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

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

# Choose a locale
set_locale "$locale"
# Clean system
include clean_system
# Define DNS server after last running systemd-nspawn.
echo "nameserver ${nameserver}" >"${work_dir}"/etc/resolv.conf
# Disable the use of http proxy in case it is enabled.
disable_proxy
# Mirror & suite replacement
restore_mirror
# Reload sources.list
#include sources.list

cd "${basedir}"
# Do the kernel stuff...
git clone --depth 1 -b v5.4.45-newport https://github.com/gateworks/linux-newport ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Don't change the version because of our patches.
touch .scmversion
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu- 
patch -p1 < ${current_dir}/patches/kali-wifi-injection-5.4.patch
patch -p1 < ${current_dir}/patches/0001-wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
cp ${current_dir}/kernel-configs/gateworks-newport-5.4.45.config .config
cp ${current_dir}/kernel-configs/gateworks-newport-5.4.45.config ${work_dir}/usr/src/gateworks-newport-5.4.45.config
#build
make -j $(grep -c processor /proc/cpuinfo)
# install compressed kernel in a kernel.itb
mkimage -f auto -A arm64 -O linux -T kernel -C gzip -n "Newport Kali Kernel" -a 20080000 -e 20080000 -d arch/arm64/boot/Image.gz kernel.itb
cp kernel.itb ${work_dir}/boot
# install kernel modules
make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${work_dir} modules_install
make INSTALL_HDR_PATH=${work_dir}/usr headers_install
# cryptodev-linux build/install
git clone --depth 1 https://github.com/cryptodev-linux/cryptodev-linux ${work_dir}/usr/src/cryptodev-linux
cd ${work_dir}/usr/src
make -C cryptodev-linux KERNEL_DIR=${work_dir}/usr/src/kernel
make -C cryptodev-linux KERNEL_DIR=${work_dir}/usr/src/kernel DESTDIR=${work_dir} INSTALL_MOD_PATH=${work_dir} install
# wireguard-linux-compat build/install
git clone --depth 1 https://git.zx2c4.com/wireguard-linux-compat ${work_dir}/usr/src/wireguard-linux-compat
make -C ${work_dir}/usr/src/kernel M=../wireguard-linux-compat/src modules
make -C ${work_dir}/usr/src/kernel M=../wireguard-linux-compat/src INSTALL_MOD_PATH=${work_dir} modules_install
# cleanup
cd ${work_dir}/usr/src/kernel
make mrproper

# U-boot script
install -m644 ${current_dir}/bsp/bootloader/gateworks-newport/newport.scr ${work_dir}/boot/newport.script
mkimage -A arm64 -T script -C none -d ${work_dir}/boot/newport.script ${work_dir}/boot/newport.scr
rm ${work_dir}/boot/newport.script

# reboot script
cat << EOF > ${work_dir}/lib/systemd/system-shutdown/gsc-poweroff
#!/bin/bash
# use GSC to power cycle the system
echo 2 > /sys/bus/i2c/devices/0-0020/powerdown
done
EOF
chmod +x ${work_dir}/lib/systemd/system-shutdown/gsc-poweroff

# Calculate the space to create the image.
root_size=$(du -s -B1 ${work_dir} --exclude=${work_dir}/boot | cut -f1)
root_extra=$((${root_size}/1024/1000*5*1024/5))
raw_size=$(($((${free_space}*1024))+${root_extra}))

# Weird Boot Partition
echo "Creating image file ${imagename}.img"
wget http://dev.gateworks.com/newport/boot_firmware/firmware-newport.img -O ${current_dir}/${imagename}.img
fallocate -l $(echo ${raw_size}Ki | numfmt --from=iec-i --to=si) ${base_dir}/${imagename}.img
dd if=${base_dir}/${imagename}.img of=${current_dir}/${imagename}.img bs=16M seek=1
echo ", +" | sfdisk -N 2 ${current_dir}/${imagename}.img

# Set the partition variables
loopdevice=`losetup -f --show ${current_dir}/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p2

# Create file systems
if [[ $fstype == ext4 ]]; then
  features="-O ^64bit,^metadata_csum"
elif [[ $fstype == ext3 ]]; then
  features="-O ^64bit"
fi
mkfs $features -t $fstype -L ROOTFS ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# Create an fstab so that we don't mount / read-only.
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${basedir}/root/

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk.
blockdev --flushbufs "${loopdevice}"
python -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Unmount partitions
umount -l ${rootp}

kpartx -dv ${loopdevice}
losetup -d ${loopdevice}

# Limite use cpu function
limit_cpu (){
  rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) # Randowm name group
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
#    limit_cpu pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p Nº cpu cores use
    pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p Nº cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  fi
else
  chmod 644 ${current_dir}/${imagename}.img
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone wrong.
echo "Removing temporary build files"
rm -rf "${basedir}"
