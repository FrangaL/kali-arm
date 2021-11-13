#!/usr/bin/env bash

log " selecting packages ..." gray

debootstrap_base="kali-archive-keyring,eatmydata"

# This is the bare minimum if you want to start from very scratch
minimal_pkgs="ca-certificates iw network-manager parted wpasupplicant sudo"

# This is the list of minimal common packages
common_min_pkgs="$minimal_pkgs apt-transport-https crda firmware-linux firmware-realtek firmware-atheros \
firmware-libertas fontconfig ifupdown initramfs-tools kali-defaults man-db mlocate netcat-traditional net-tools \
pciutils psmisc rfkill screen snmpd snmp tftp tmux unrar usbutils vim zerofree \
zsh zsh-autosuggestions zsh-syntax-highlighting"
# This is the list of common packages
common_pkgs="$minimal_pkgs kali-linux-core apt-transport-https bluez bluez-firmware dialog \
ifupdown initramfs-tools inxi libnss-systemd man-db mlocate net-tools network-manager crda \
pciutils psmisc rfkill screen snmpd snmp tftp triggerhappy unrar usbutils whiptail zerofree"

services="apache2 atftpd ssh openvpn tightvncserver"

# This is the list of minimal cli based tools
cli_min_tools="aircrack-ng crunch cewl dnsrecon dnsutils ethtool exploitdb hydra john \
libnfc-bin medusa metasploit-framework mfoc ncrack nmap passing-the-hash proxychains recon-ng \
sqlmap tcpdump theharvester tor tshark whois windows-binaries winexe wpscan"
# This is the list of most cli based tools
cli_tools_pkgs="kali-linux-arm"

# Desktop packages to install
case $desktop in
  xfce|gnome|kde|i3|i3-gaps|lxde|mate|e17)
    desktop_pkgs="kali-linux-default kali-desktop-$desktop alsa-utils xfonts-terminus \
    xinput xserver-xorg-video-fbdev xserver-xorg-input-libinput" ;;
  none|slim|miminal) variant="minimal"; minimal="1"; desktop_pkgs="" ;;
esac

# Installed kernel sources when using a kernel that isn't packaged.
custom_kernel_pkgs="bc bison libssl-dev"

rpi_pkgs="fake-hwclock ntpdate u-boot-tools"

# Packages specific to the boards and using the GPIO on it
gpio_pkgs="i2c-tools python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus"

# Add swap packages
if [ "$swap" = yes ]; then
  minimal_pkgs+=" dphys-swapfile"
fi

extra="$custom_kernel_pkgs"

# add extra_custom_pkgs, that can be a global variable
packages="$common_pkgs $cli_tools_pkgs $services $extra_custom_pkgs"

# Do not add re4son_pkgs to this list, as we do not have his repo added when these are installed
if [[ "$hw_model" == *rpi* ]]; then
  extra+=" $gpio_pkgs $rpi_pkgs"
fi
if [ "$minimal" = "1" ]; then
  image_mode="minimal"
  if [ "$slim" = "1" ]; then
    cli_min_tools=""
    image_mode="slim"
    packages="$common_min_pkgs $cli_min_tools ssh"
  else
    packages="$common_min_pkgs $cli_min_tools $services $extra_custom_pkgs"
  fi
  log " selecting $image_mode mode ..." gray
fi

# Basic packages third stage
third_stage_pkgs="binutils ca-certificates console-common console-setup locales libterm-readline-gnu-perl git wget curl"

# Re4son packages
re4son_pkgs="kalipi-kernel kalipi-bootloader kalipi-re4son-firmware kalipi-kernel-headers kalipi-config kalipi-tft-config pi-bluetooth bluetooth bluez bluez-firmware"
# PiTail specific packages
pitail_pkgs="bluelog bluesnarfer blueranger bluez-tools bridge-utils wifiphisher cmake mailutils libusb-1.0-0-dev htop locate pure-ftpd tigervnc-standalone-server dnsmasq darkstat"
