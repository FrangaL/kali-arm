#!/usr/bin/env bash

log " selecting packages ..." gray

debootstrap_base="kali-archive-keyring,eatmydata"

# This is the bare minimum if you want to start from very scratch
minimal_pkgs="ca-certificates iw network-manager parted sudo wpasupplicant"

# This is the list of minimal common packages
common_min_pkgs="$minimal_pkgs apt-transport-https command-not-found \
fontconfig ifupdown kali-defaults kali-tweaks man-db mlocate net-tools \
netcat-traditional pciutils psmisc rfkill screen snmp snmpd tftp tmux unrar \
usbutils vim wireless-regdb zerofree zsh zsh-autosuggestions \
zsh-syntax-highlighting"

# This is the list of common packages
common_pkgs="$minimal_pkgs apt-transport-https dialog \
ifupdown inxi kali-linux-core libnss-systemd man-db mlocate net-tools \
network-manager pciutils psmisc rfkill screen snmp snmpd tftp \
triggerhappy usbutils whiptail zerofree"

services="apache2 atftpd openvpn ssh tightvncserver"

extra_custom_pkgs=""

# This is the list of most cli based tools
cli_tools_pkgs="kali-linux-headless"

# Desktop packages to install
case $desktop in
    xfce | gnome | kde | i3 | i3-gaps | lxde | mate | e17)
        desktop_pkgs="kali-linux-default kali-desktop-$desktop alsa-utils \
        xfonts-terminus xinput xserver-xorg-video-fbdev \xserver-xorg-input-libinput" ;;

    none | slim | miminal) 
        variant="minimal"; minimal="1"; desktop_pkgs="" ;;

esac

# Installed kernel sources when using a kernel that isn't packaged.
custom_kernel_pkgs="bc bison libssl-dev"

rpi_pkgs="kali-sbc-raspberrypi"

# Add swap packages
if [ "$swap" = yes ]; then
    minimal_pkgs+=" dphys-swapfile"

fi

extra="$custom_kernel_pkgs"

# add extra_custom_pkgs, that can be a global variable
packages="$common_pkgs $cli_tools_pkgs $services $extra_custom_pkgs"

# Do not add re4son_pkgs to this list, as we do not have his repo added when these are installed
if [[ "$hw_model" == *rpi* ]]; then
    extra+="$rpi_pkgs"

fi

if [ "$minimal" = "1" ]; then
    image_mode="minimal"

    if [ "$slim" = "1" ]; then
        image_mode="slim"
        packages="$common_min_pkgs ssh"

    else
        packages="$common_min_pkgs $services $extra_custom_pkgs"

    fi

    log " selecting $image_mode mode ..." gray

fi

# Basic packages third stage
third_stage_pkgs="binutils ca-certificates console-common console-setup curl \
git libterm-readline-gnu-perl locales wget"

# Re4son packages
re4son_pkgs="kalipi-bootloader kalipi-kernel kalipi-kernel-headers \
kalipi-re4son-firmware"

# PiTail specific packages
pitail_pkgs="bluelog blueranger bluesnarfer bluez-tools bridge-utils cmake \
darkstat dnsmasq htop libusb-1.0-0-dev locate mailutils pure-ftpd 
tigervnc-standalone-server wifiphisher"
