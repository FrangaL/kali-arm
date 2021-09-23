#!/usr/bin/env bash
#
# Kali Linux ARM build-script for NanoPi NEO Plus2 (Minimal)
# https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a community script - you will need to generate your own image to use
# More information: https://www.kali.org/docs/arm/nanopi-neo-plus2/
#

# Stop on error
set -e

# shellcheck disable=SC2154
# Load general functions
# shellcheck source=/dev/null
source ./common.d/functions.sh

# Hardware model
hw_model=${hw_model:-"nanopi-neo-plus2"}
# Architecture
architecture=${architecture:-"arm64"}
# Variant name for image and dir build
variant=${variant:-"minimal-${architecture}"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"none"}

# Load common variables
include variables
# Checks script environment
include check
# Packages build list
include packages
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
set_hostname "neoplus2"
# Network configs
include network
add_interface eth0

# Copy directory bsp into build dir
status "Copy directory bsp into build dir"
cp -rp bsp "${work_dir}"

# Eventually this should become a systemd service, but for now, we use the same
# init.d file that they provide and we let systemd handle the conversion
mkdir -p ${work_dir}/etc/init.d/
cat << EOF > ${work_dir}/etc/init.d/brcm_patchram_plus
#!/usr/bin/env bash

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
chmod 0755 ${work_dir}/etc/init.d/brcm_patchram_plus

# Third stage
cat <<EOF > "${work_dir}"/third-stage
#!/usr/bin/env bash
set -e
status_3i=0
status_3t=\$(grep '^status_stage3 ' \$0 | wc -l)

status_stage3() {
  status_3i=\$((status_3i+1))
  echo  " [i] Stage 3 (\${status_3i}/\${status_3t}): \$1"
}

status_stage3 'Update apt'
export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update

status_stage3 'Install core packages'
eatmydata apt-get -y install ${third_stage_pkgs}

eatmydata apt-get install -y ${minimal_pkgs} || eatmydata apt-get install -y --fix-broken

status_stage3 'Install u-boot package'
eatmydata apt-get install -y u-boot-sunxi linux-image-arm64 u-boot-menu

eatmydata apt-get -y --purge autoremove

status_stage3 'Linux console/keyboard configuration'
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

status_stage3 'Copy all services'
cp -p /bsp/services/all/*.service /etc/systemd/system/

status_stage3 'Copy script rpi-resizerootfs'
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/
install -m755 /bsp/scripts/growpart /usr/local/bin/

status_stage3 'Enable rpi-resizerootfs first boot'
systemctl enable rpi-resizerootfs

status_stage3 'Generate SSH host keys on first run'
systemctl enable regenerate_ssh_host_keys

status_stage3 'Enable ssh service'
systemctl enable ssh

status_stage3 'Theres no graphical output on this device'
systemctl set-default multi-user

status_stage3 'Install ca-certificate'
cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

status_stage3 '# Set a REGDOMAIN'
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda || true

status_stage3 'Try and make the console a bit nicer. Set the terminus font for a bit nicer display'
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

status_stage3 'Fix startup time from 5 minutes to 15 secs on raise interface wlan0'
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

status_stage3 'Enable runonce'
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

status_stage3 'Clean up dpkg.eatmydata'
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 0755 "${work_dir}"/third-stage
status "Run third stage"
systemd-nspawn_exec /third-stage

# Clean system
include clean_system
trap clean_build ERR SIGTERM SIGINT

cd "${current_dir}/"

# Copy over the firmware for the ap6212 wifi
# On the neo plus2 default install there are other firmware files installed for
# p2p and apsta but I can't find them publicly posted to friendlyarm's GitHub
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon
status "WiFi firmware"
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
status 'Create firmware symlinks'
mkdir -p ${work_dir}/lib/firmware/brcm
cd ${work_dir}/lib/firmware/brcm
ln -s /lib/firmware/ap6212/fw_bcm43438a1.bin brcmfmac43430a1-sdio.bin
ln -s /lib/firmware/ap6212/nvram_ap6212.txt brcmfmac43430a1-sdio.txt
ln -s /lib/firmware/ap6212/fw_bcm43438a0.bin brcmfmac43430-sdio.bin
ln -s /lib/firmware/ap6212/nvram.txt brcmfmac43430-sdio.txt
cd "${current_dir}/"

cd "${current_dir}/"

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary $fstype 32MiB 100%

# Set the partition variables
loopdevice=$(losetup --show -fP "${image_dir}/${image_name}.img")
rootp="${loopdevice}p1"

# Create file systems
status "Formatting partitions"
if [[ "$fstype" == "ext4" ]]; then
  features="^64bit,^metadata_csum"
elif [[ "$fstype" == "ext3" ]]; then
  features="^64bit"
fi
mkfs -O "$features" -t "$fstype" -L ROOTFS "${rootp}"

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/
mount "${rootp}" "${base_dir}"/root

# Create an fstab so that we don't mount / read-only
status "/etc/fstab"
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

status 'Update extlinux.conf with the correct root partition UUID'
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot
# We do this down here because we don't know the UUID until after the image is created
sed -i -e "0,/root=.*/s//root=UUID=$(blkid -s UUID -o value ${rootp}) rootfstype=$fstype console=ttyS0,115200 console=tty1 consoleblank=0 rw quiet rootwait/g" ${work_dir}/boot/extlinux/extlinux.conf
# And we remove the "Debian GNU/Linux because we're Kali"
sed -i -e "s/Debian GNU\/Linux/Kali Linux/g" ${work_dir}/boot/extlinux/extlinux.conf

status "Rsyncing rootfs into image file"
rsync -HPavz -q "${work_dir}"/ "${base_dir}"/root/
sync

status "Write u-boot to the loopdevice"
TARGET="${work_dir}/usr/lib/u-boot/nanopi_neo_plus2" "${work_dir}"/usr/bin/u-boot-install-sunxi64 ${loopdevice}

cd "${current_dir}/"

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk
blockdev --flushbufs "${loopdevice}"
python -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Unmount filesystem
status "Unmount filesystem"
umount -l "${rootp}"

# Check filesystem
status "Check filesystem"
e2fsck -y -f "${rootp}"

# Remove loop devices
status "Remove loop devices"
kpartx -dv "${loopdevice}" 
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories
# Comment this out to keep things around if you want to see what may have gone wrong
clean_build
