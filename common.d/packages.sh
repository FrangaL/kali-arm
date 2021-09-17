#!/usr/bin/env bash

log "selecting packages" green

# This is the bare minimum if you want to start from very scratch.
minimal_pkgs="ca-certificates iw parted ssh wpasupplicant"

# This is the list of minimal common packages
common_min_pkgs="apt-transport-https firmware-linux firmware-realtek firmware-atheros \
firmware-libertas ifupdown initramfs-tools kali-defaults man-db mlocate netcat-traditional net-tools \
parted pciutils psmisc rfkill screen snmpd snmp sudo tftp tmux unrar usbutils zerofree crda iw"
# This is the list of common packages
common_pkgs="kali-linux-core apt-transport-https bluez bluez-firmware dialog \
ifupdown initramfs-tools inxi iw libnss-systemd man-db mlocate net-tools network-manager crda \
pciutils psmisc rfkill screen snmpd snmp sudo tftp triggerhappy unrar usbutils whiptail zerofree"

services="apache2 atftpd openssh-server openvpn tightvncserver"

# This is the list of minimal cli based tools
cli_min_tools="aircrack-ng crunch cewl dnsrecon dnsutils ethtool exploitdb hydra john \
libnfc-bin medusa metasploit-framework mfoc ncrack nmap passing-the-hash proxychains recon-ng \
sqlmap tcpdump theharvester tor tshark whois windows-binaries winexe wpscan"
# This is the list of most cli based tools
cli_tools_pkgs="kali-linux-arm"

# Desktop packages to install
if [[ "$desktop" == "none" ]]; then
  desktop_pkgs=""
else
  desktop_pkgs="kali-linux-default kali-desktop-$desktop alsa-utils xfonts-terminus \
  xinput xserver-xorg-video-fbdev xserver-xorg-input-libinput xserver-xorg-input-synaptics"
fi

# Installed kernel sources when using a kernel that isn't packaged.
custom_kernel_pkgs="bc bison libssl-dev"

rpi_pkgs="fake-hwclock ntpdate u-boot-tools"

# Packages specific to the boards and using the GPIO on it
gpio_pkgs="i2c-tools python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus"

extra="$custom_kernel_pkgs"
packages="$common_pkgs $cli_tools_pkgs $services"

if [[ "$hw_model" == *rpi* ]]; then
  extra+=" $gpio_pkgs $rpi_pkgs"
fi
if [[ "$variant" == *lite* ]]; then
  packages="$common_min_pkgs $cli_min_tools $services"
fi

third_stage_pkgs="binutils ca-certificates console-common console-setup locales libterm-readline-gnu-perl git wget curl"
