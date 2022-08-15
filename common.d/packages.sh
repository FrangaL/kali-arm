#!/usr/bin/env bash

log " selecting packages ..." gray

# This list is included by debootstrap and has to be comma separated.
debootstrap_base="kali-archive-keyring,ca-certificates,eatmydata,iw,parted,sudo,wpasupplicant"

# This is the list of minimal common packages
common_pkgs="kali-linux-core apt-transport-https bluez bluez-firmware dialog \
firmware-linux firmware-realtek firmware-atheros firmware-libertas fontconfig \
initramfs-tools inxi libnss-systemd net-tools network-manager pciutils psmisc \
tmux triggerhappy usbutils vim wireless-regdb zerofree"

services="ssh openvpn tightvncserver"

allwinner="u-boot-menu u-boot-sunxi u-boot-tools"
amlogic="u-boot-amlogic u-boot-menu u-boot-tools"
qualcomm="qrtr rmtfs tqftpserv firmware-qcom-soc"
rasperrypi="fake-hwclock kalipi-config kalipi-tft-config pi-bluetooth pigpio-tools python3-rpi.gpio python3-smbus"
rockchip="u-boot-menu u-boot-rockchip u-boot-tools"

# This is the list of most cli based tools
cli_tools_pkgs="kali-linux-headless"

# Desktop packages to install
case $desktop in
  xfce|gnome|kde|i3|i3-gaps|lxde|mate|e17)
    desktop_pkgs="kali-linux-default kali-desktop-$desktop alsa-utils xfonts-terminus \
    xinput xserver-xorg-video-fbdev xserver-xorg-input-libinput" ;;
  none|slim|miminal) variant="minimal"; minimal="1"; desktop_pkgs="" ;;
esac

# Installed kernel sources when using a kernel that isn't packaged.
custom_kernel_pkgs="bc bison libssl-dev"

# Add swap packages
if [ "$swap" = yes ]; then
  minimal_pkgs+=" dphys-swapfile"
fi

extra="$custom_kernel_pkgs"

# Do not add re4son_pkgs to this list, as we do not have his repo added when these are installed
if [[ "$hw_model" == *rpi* ]]; then
  extra+=" $raspberrypi"
fi
if [ "$minimal" = "1" ]; then
  image_mode="minimal"
  if [ "$slim" = "1" ]; then
    cli_tools_pkgs=""
    image_mode="slim"
    packages="$common_pkgs $extra"
  else
    packages="kali-linux-default $common_pkgs $cli_tools_pkgs $services $extra_custom_pkgs $extra"
  fi
  log " selecting $image_mode mode ..." gray
fi

# Basic packages third stage
third_stage_pkgs="binutils console-common console-setup locales libterm-readline-gnu-perl wget curl"

# Re4son packages
re4son_pkgs="kalipi-kernel kalipi-bootloader kalipi-re4son-firmware kalipi-kernel-headers"
# PiTail specific packages
pitail_pkgs="bluelog bluesnarfer blueranger bluez-tools bridge-utils wifiphisher cmake mailutils libusb-1.0-0-dev htop locate pure-ftpd tigervnc-standalone-server dnsmasq darkstat"
