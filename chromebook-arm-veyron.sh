#!/bin/bash
set -e

# Uncomment to activate debug
# debug=true

if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"armhf"}
# Generate a random machine name to be used.
machine=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c16 ; echo)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-veyron}
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
basedir=${current_dir}/veyron-"$1"
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
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xserver-xorg-input-libinput xserver-xorg-input-synaptics xfonts-terminus xinput"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware florence kali-linux-core libnss-systemd libssl-dev triggerhappy"

packages="${arm} ${base} ${services}"

kernel_release="R83-13020.B-chromeos-4.19"

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
  qemu_bin=/usr/bin/qemu-arm-static
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

cat << EOF > ${work_dir}/third-stage
#!/bin/bash -e
export DEBIAN_FRONTEND=noninteractive
export RUNLEVEL=1
ln -sf /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update

apt-get -y install git-core binutils ca-certificates cryptsetup-bin initramfs-tools locales console-common less nano git u-boot-tools

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
apt-get dist-upgrade

apt-get -y --allow-change-held-packages --purge autoremove

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

# Copy over the default bashrc
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

cat << EOF > ${work_dir}/etc/resolv.conf
nameserver 8.8.8.8
EOF

cd ${basedir}

# Kernel section.  If you want to use a custom kernel, or configuration, replace
# them in this section.
# Mainline kernel branch
git clone --depth 1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git -b linux-4.19.y ${work_dir}/usr/src/kernel
# ChromeOS kernel branch
#git clone --depth 1 https://chromium.googlesource.com/chromiumos/third_party/kernel.git -b release-${kernel_release} ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
# Mainline kernel config
cp ${basedir}/../kernel-configs/veyron-4.19.config .config
# (Currently not working) chromeos-based kernel config
#cp ${basedir}/../kernel-configs/veyron-4.19-cros.config .config
cp .config ${work_dir}/usr/src/veyron.config
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed.
export CROSS_COMPILE=arm-linux-gnueabihf-
# This allows us to patch the kernel without it adding -dirty to the kernel version.
touch .scmversion
patch -p1 --no-backup-if-mismatch < ${basedir}/../patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 --no-backup-if-mismatch < ${basedir}/../patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make -j$(grep -c processor /proc/cpuinfo)
make dtbs
make modules_install INSTALL_MOD_PATH=${work_dir}
cat << __EOF__ > ${work_dir}/usr/src/kernel/arch/arm/boot/kernel-veyron.its
/dts-v1/;

/ {
    description = "Chrome OS kernel image with one or more FDT blobs";
    images {
        kernel@1{
            description = "kernel";
            data = /incbin/("zImage");
            type = "kernel_noload";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0>;
            entry = <0>;
        };
        fdt@1{
            description = "rk3288-veyron-brain.dtb";
            data = /incbin/("dts/rk3288-veyron-brain.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@2{
            description = "rk3288-veyron-jaq.dtb";
            data = /incbin/("dts/rk3288-veyron-jaq.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@3{
            description = "rk3288-veyron-jerry.dtb";
            data = /incbin/("dts/rk3288-veyron-jerry.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@4{
            description = "rk3288-veyron-mickey.dtb";
            data = /incbin/("dts/rk3288-veyron-mickey.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@5{
            description = "rk3288-veyron-minnie.dtb";
            data = /incbin/("dts/rk3288-veyron-minnie.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1{
                algo = "sha1";
            };
        };
        fdt@6{
	    description = "rk3288-veyron-pinky.dtb";
	    data = /incbin/("dts/rk3288-veyron-pinky.dtb");
	    type = "flat_dt";
	    arch = "arm";
	    compression = "none";
	    hash@1{
		algo = "sha1";
	    };
	};
        fdt@7{
	    description = "rk3288-veyron-speedy.dtb";
	    data = /incbin/("dts/rk3288-veyron-speedy.dtb");
	    type = "flat_dt";
	    arch = "arm";
	    compression = "none";
	    hash@1{
		algo = "sha1";
	    };
	};
    };
    configurations {
        default = "conf@1";
        conf@1{
            kernel = "kernel@1";
            fdt = "fdt@1";
        };
        conf@2{
            kernel = "kernel@1";
            fdt = "fdt@2";
        };
        conf@3{
            kernel = "kernel@1";
            fdt = "fdt@3";
        };
        conf@4{
            kernel = "kernel@1";
            fdt = "fdt@4";
        };
        conf@5{
            kernel = "kernel@1";
            fdt = "fdt@5";
        };
	    conf@6{
	        kernel = "kernel@1";
	        fdt = "fdt@6";
	    };
	    conf@7{
	        kernel = "kernel@1";
	        fdt = "fdt@7";
	    };
    };
};
__EOF__
cd ${work_dir}}/usr/src/kernel/arch/arm/boot
mkimage -D "-I dts -O dtb -p 2048" -f kernel-veyron.its veyron-kernel

# BEHOLD THE MAGIC OF PARTUUID/PARTNROFF
echo 'noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=ext3' > cmdline

# Pulled from ChromeOS, this is exactly what they do because there's no
# bootloader in the kernel partition on ARM.
dd if=/dev/zero of=bootloader.bin bs=512 count=1

vbutil_kernel --arch arm --pack "${basedir}"/kernel.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline --bootloader bootloader.bin --vmlinuz veyron-kernel
cd ${work_dir}}/usr/src/kernel
make mrproper
cp ${basedir}/../kernel-configs/veyron-4.19.config .config
#cp ${basedir}/../kernel-configs/veyron-4.19-cros.config .config
cd ${basedir}

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd ${basedir}

# Disable uap0 and p2p0 interfaces in NetworkManager
mkdir -p ${work_dir}/etc/NetworkManager/
echo -e '\n[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> ${work_dir}/etc/NetworkManager/NetworkManager.conf

# Create these if they don't exist, to make sure we have proper audio with pulse
mkdir -p ${work_dir}/var/lib/alsa/
cp ${basedir}/../bsp/audio/veyron/asound.state ${work_dir}/var/lib/alsa/asound.state
cp ${basedir}/../bsp/audio/veyron/default.pa ${work_dir}/etc/pulse/default.pa

# mali rules so users can access the mali0 driver...
cp ${basedir}/../bsp/udev/50-mali.rules ${work_dir}/etc/udev/rules.d/50-mali.rules
cp ${basedir}/../bsp/udev/50-media.rules ${work_dir}/etc/udev/rules.d/50-media.rules
# EHCI is apparently quirky.
cp ${basedir}/../bsp/udev/99-rk3288-ehci-persist.rules ${work_dir}/etc/udev/rules.d/99-rk3288-ehci-persist.rules
# Avoid gpio charger wakeup system
cp ${basedir}/../bsp/udev/99-rk3288-gpio-charger.rules ${work_dir}/etc/udev/rules.d/99-rk3288-gpio-charger.rules
# Rule used to kick start the bluetooth/wifi chip.
cp ${basedir}/../bsp/udev/80-brcm-sdio-added.rules ${work_dir}/etc/udev/rules.d/80-brcm-sdio-added.rules
# Hide the eMMC partitions from udisks
cp ${basedir}/../bsp/udev/99-hide-emmc-partitions.rules ${work_dir}/etc/udev/rules.d/99-hide-emmc-partitions.rules

# disable btdsio
mkdir -p ${work_dir}/etc/modprobe.d/
cat << EOF > ${work_dir}/etc/modprobe.d/blacklist-btsdio.conf
blacklist btsdio
EOF

# Touchpad configuration
mkdir -p ${work_dir}/etc/X11/xorg.conf.d
cp ${basedir}/../bsp/xorg/10-synaptics-chromebook.conf ${work_dir}/etc/X11/xorg.conf.d/

# Copy the broadcom firmware files in.
mkdir -p ${work_dir}/lib/firmware/brcm/
cp ${basedir}/../bsp/firmware/veyron/brcm* ${work_dir}/lib/firmware/brcm/
cp ${basedir}/../bsp/firmware/veyron/BCM* ${work_dir}/lib/firmware/brcm/
# Copy in the touchpad firmwares - same as above.
cp ${basedir}/../bsp/firmware/veyron/elan* ${work_dir}/lib/firmware/
cp ${basedir}/../bsp/firmware/veyron/max* ${work_dir}/lib/firmware/
cd ${basedir}

# We need to kick start the sdio chip to get bluetooth/wifi going.
cp ${basedir}/../bsp/firmware/veyron/brcm_patchram_plus ${work_dir}/usr/sbin/

# Calculate the space to create the image.
free_space=$((${free_space}*1024))
bootstart=$((${bootsize}*1024/1000*2*1024/2))
bootend=$((${bootstart}+1024))
rootsize=$(du -s --block-size KiB ${work_dir} --exclude boot | cut -f1)
rootsize=$((${free_space}+${rootsize//KiB/ }/1000*2*1024/2))
raw_size=$((${free_space}+${rootsize}+${bootstart}))

# Create the disk and partition it
echo "Creating image file for Veyron Chromebooks"
dd if=/dev/zero of=${basedir}/${imagename}.img bs=1KiB count=0 seek=${raw_size} && sync
parted ${basedir}/${imagename}.img --script -- mklabel gpt
cgpt create -z ${basedir}/${imagename}.img
cgpt create ${basedir}/${imagename}.img

cgpt add -i 1 -t kernel -b 8192 -s 32768 -l kernel -S 1 -T 5 -P 10 ${basedir}/${imagename}.img
cgpt add -i 2 -t data -b 40960 -s `expr $(cgpt show ${basedir}/${imagename}.img | grep 'Sec GPT table' | awk '{ print \$1 }')  - 40960` -l Root ${basedir}/${imagename}.img

loopdevice=`losetup -f --show ${basedir}/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

mkfs.ext3 -O ^64bit -O ^flex_bg -O ^metadata_csum -L rootfs ${rootp}

mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# Create an fstab so that we don't mount / read-only.
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               ext3    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${basedir}/root/

# Unmount partitions
sync
umount ${rootp}

dd if=${basedir}/kernel.bin of=${bootp}

cgpt repair ${loopdevice}

kpartx -dv ${loopdevice}
losetup -d ${loopdevice}

# Don't pixz on 32bit, there isn't enough memory to compress the images.
if [ $(arch) == 'x86_64' ]; then
	echo "Compressing ${imagename}.img"
  cd ${current_dir}
	rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) #Random name group
	cgcreate -g cpu:/cpulimit-${rand} # Name of group
	cgset -r cpu.shares=800 cpulimit-${rand} #Max 1024
	cgset -r cpu.cfs_quota_us=80000 cpulimit-${rand} # Max 10000
	cgexec -g cpu:cpulimit-${rand} pixz -p 2 "${basedir}"/${imagename}.img ${imagename}.img.xz # -p Number of cpu cores to use
	cgdelete cpu:/cpulimit-${rand} # Delete group
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Removing temporary build files"
rm -rf "${basedir}"