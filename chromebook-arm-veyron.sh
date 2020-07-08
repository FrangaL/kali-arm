#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/veyron-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-veyron}
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
export CROSS_COMPILE=arm-linux-gnueabihf-
if [ $(compgen -c $CROSS_COMPILE | wc -l) -eq 0 ] ; then
    echo "Missing cross compiler. Set up PATH according to the README"
    exit 1
fi
# Unset CROSS_COMPILE so that if there is any native compiling needed it doesn't
# get cross compiled.
unset CROSS_COMPILE

# Package installations for various sections.
# This will build a minimal Kali system with XFCE and a few tools.
# This is the section to edit if you would like to add more packages.
# See http://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
# use.  You can also install packages, using just the package name, but keep in
# mind that not all packages work on ARM! If you specify one of those, the
# script will throw an error, but will still continue on, and create an unusable
# image, keep that in mind.

arm="kali-linux-arm ntpdate"
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen tmux unrar usbutils vim wget zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xserver-xorg-input-libinput xserver-xorg-input-synaptics xfonts-terminus xinput"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison bluez bluez-firmware florence kali-linux-core libnss-systemd libssl-dev triggerhappy"

packages="${arm} ${base} ${services}"
architecture="armhf"
# If you have your own preferred mirrors, set them here.
# After generating the rootfs, we set the sources.list to the default settings.
mirror=http.kali.org

kernel_release="R83-13020.B-chromeos-4.19"

# Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
# to unset it.
#export http_proxy="http://localhost:3142/"

mkdir -p "${basedir}"
cd "${basedir}"

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring --arch ${architecture} ${suite} kali-${architecture} http://${mirror}/kali

cp /usr/bin/qemu-arm-static kali-${architecture}/usr/bin/

LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /debootstrap/debootstrap --second-stage

mkdir -p kali-${architecture}/etc/apt/
cat << EOF > kali-${architecture}/etc/apt/sources.list
deb http://${mirror}/kali ${suite} main contrib non-free
EOF

# Set hostname
echo "${hostname}" > kali-${architecture}/etc/hostname

# So X doesn't complain, we add kali to hosts
cat << EOF > kali-${architecture}/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

mkdir -p mkdir -p kali-${architecture}/etc/network/
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

#mount -t proc proc kali-$architecture/proc
#mount -o bind /dev/ kali-$architecture/dev/
#mount -o bind /dev/pts kali-$architecture/dev/pts

cat << EOF > kali-${architecture}/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

mkdir -p kali-${architecture}/usr/lib/systemd/system/
cp "${basedir}"/../bsp/services/all/*.service kali-${architecture}/usr/lib/systemd/system/

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

# Copy over the default bashrc
cp  /etc/skel/.bashrc /root/.bashrc

cd /root
apt download ca-certificates
apt download libgdk-pixbuf2.0-0
apt download fontconfig
apt download kali-menu

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

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

cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

#umount kali-$architecture/proc/sys/fs/binfmt_misc
#umount kali-$architecture/dev/pts
#umount kali-$architecture/dev/
#umount kali-$architecture/proc

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main contrib non-free
deb-src http://http.kali.org/kali kali-rolling main contrib non-free
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

cd "${basedir}"

# Kernel section.  If you want to use a custom kernel, or configuration, replace
# them in this section.
# Mainline kernel branch
git clone --depth 1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux.git -b linux-4.19.y "${basedir}"/kali-${architecture}/usr/src/kernel
# ChromeOS kernel branch
#git clone --depth 1 https://chromium.googlesource.com/chromiumos/third_party/kernel.git -b release-${kernel_release} "${basedir}"/kali-${architecture}/usr/src/kernel
cd "${basedir}"/kali-${architecture}/usr/src/kernel
# Mainline kernel config
cp "${basedir}"/../kernel-configs/veyron-4.19.config .config
# (Currently not working) chromeos-based kernel config
#cp "${basedir}"/../kernel-configs/veyron-4.19-cros.config .config
cp .config "${basedir}"/kali-${architecture}/usr/src/veyron.config
export ARCH=arm
# Edit the CROSS_COMPILE variable as needed.
export CROSS_COMPILE=arm-linux-gnueabihf-
# This allows us to patch the kernel without it adding -dirty to the kernel version.
touch .scmversion
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 --no-backup-if-mismatch < "${basedir}"/../patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
make -j$(grep -c processor /proc/cpuinfo)
make dtbs
make modules_install INSTALL_MOD_PATH="${basedir}"/kali-${architecture}
cat << __EOF__ > "${basedir}"/kali-${architecture}/usr/src/kernel/arch/arm/boot/kernel-veyron.its
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
cd "${basedir}"/kali-${architecture}/usr/src/kernel/arch/arm/boot
mkimage -D "-I dts -O dtb -p 2048" -f kernel-veyron.its veyron-kernel

# BEHOLD THE MAGIC OF PARTUUID/PARTNROFF
echo 'noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=ext3' > cmdline

# Pulled from ChromeOS, this is exactly what they do because there's no
# bootloader in the kernel partition on ARM.
dd if=/dev/zero of=bootloader.bin bs=512 count=1

vbutil_kernel --arch arm --pack "${basedir}"/kernel.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline --bootloader bootloader.bin --vmlinuz veyron-kernel
cd "${basedir}"/kali-${architecture}/usr/src/kernel
make mrproper
cp "${basedir}"/../kernel-configs/veyron-4.19.config .config
#cp "${basedir}"/../kernel-configs/veyron-4.19-cros.config .config
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

# Disable uap0 and p2p0 interfaces in NetworkManager
mkdir -p "${basedir}"/kali-${architecture}/etc/NetworkManager/
echo -e '\n[keyfile]\nunmanaged-devices=interface-name:p2p0\n' >> "${basedir}"/kali-${architecture}/etc/NetworkManager/NetworkManager.conf

# Create these if they don't exist, to make sure we have proper audio with pulse
mkdir -p "${basedir}"/kali-${architecture}/var/lib/alsa/
cp "${basedir}"/../bsp/audio/veyron/asound.state kali-${architecture}/var/lib/alsa/asound.state
cp "${basedir}"/../bsp/audio/veyron/default.pa "${basedir}"/kali-${architecture}/etc/pulse/default.pa

# mali rules so users can access the mali0 driver...
cp "${basedir}"/../bsp/udev/50-mali.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/50-mali.rules
cp "${basedir}"/../bsp/udev/50-media.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/50-media.rules
# EHCI is apparently quirky.
cp "${basedir}"/../bsp/udev/99-rk3288-ehci-persist.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/99-rk3288-ehci-persist.rules
# Avoid gpio charger wakeup system
cp "${basedir}"/../bsp/udev/99-rk3288-gpio-charger.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/99-rk3288-gpio-charger.rules
# Rule used to kick start the bluetooth/wifi chip.
cp "${basedir}"/../bsp/udev/80-brcm-sdio-added.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/80-brcm-sdio-added.rules
# Hide the eMMC partitions from udisks
cp "${basedir}"/../bsp/udev/99-hide-emmc-partitions.rules "${basedir}"/kali-${architecture}/etc/udev/rules.d/99-hide-emmc-partitions.rules

# disable btdsio
mkdir -p "${basedir}"/kali-${architecture}/etc/modprobe.d/
cat << EOF > "${basedir}"/kali-${architecture}/etc/modprobe.d/blacklist-btsdio.conf
blacklist btsdio
EOF

# Touchpad configuration
mkdir -p "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d
cp "${basedir}"/../bsp/xorg/10-synaptics-chromebook.conf "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/

# Copy the broadcom firmware files in.
mkdir -p "${basedir}"/kali-${architecture}/lib/firmware/brcm/
cp "${basedir}"/../bsp/firmware/veyron/brcm* "${basedir}"/kali-${architecture}/lib/firmware/brcm/
cp "${basedir}"/../bsp/firmware/veyron/BCM* "${basedir}"/kali-${architecture}/lib/firmware/brcm/
# Copy in the touchpad firmwares - same as above.
cp "${basedir}"/../bsp/firmware/veyron/elan* "${basedir}"/kali-${architecture}/lib/firmware/
cp "${basedir}"/../bsp/firmware/veyron/max* "${basedir}"/kali-${architecture}/lib/firmware/
cd "${basedir}"

# We need to kick start the sdio chip to get bluetooth/wifi going.
cp "${basedir}"/../bsp/firmware/veyron/brcm_patchram_plus "${basedir}"/kali-${architecture}/usr/sbin/

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config

echo "Creating image file for Veyron Chromebooks"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=1M count=${size}
parted ${imagename}.img --script -- mklabel gpt
cgpt create -z ${imagename}.img
cgpt create ${imagename}.img

cgpt add -i 1 -t kernel -b 8192 -s 32768 -l kernel -S 1 -T 5 -P 10 ${imagename}.img
cgpt add -i 2 -t data -b 40960 -s `expr $(cgpt show ${imagename}.img | grep 'Sec GPT table' | awk '{ print \$1 }')  - 40960` -l Root ${imagename}.img

loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

mkfs.ext3 -O ^64bit -O ^flex_bg -O ^metadata_csum -L rootfs ${rootp}

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

# Unmount partitions
sync
umount ${rootp}

dd if="${basedir}"/kernel.bin of=${bootp}

cgpt repair ${loopdevice}

kpartx -dv ${loopdevice}
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
echo "Removing temporary build files"
rm -rf "${basedir}"
