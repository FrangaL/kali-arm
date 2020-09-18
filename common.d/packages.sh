#!/usr/bin/env bash



# Packages list
arm="kali-linux-arm kali-linux-core"
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi man-db net-tools parted pciutils psmisc screen usbutils wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xserver-xorg-input-libinput xserver-xorg-input-synaptics xfonts-terminus xinput gg alsa-utils"
tools="kali-linux-default"
services="apache2 atftpd ntpdate"
extras="bc bison bluez bluez-firmware libnss-systemd libssl-dev triggerhappy crda"
third_stage_pkgs="binutils ca-certificates locales console-common console-setup less nano git"

if [[ "$hw_model" == *rpi* ]]; then
  extras="bluez bluez-firmware i2c-tools python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus triggerhappy wpasupplicant crda"
  rpi=" python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus i2c-tools"
  extra+="$rpi"
elif [[ "$variant" == *lite* ]]; then
  arm="fake-hwclock ntpdate u-boot-tools"
  base="apt-transport-https apt-utils console-setup e2fsprogs firmware-linux firmware-realtek firmware-atheros firmware-libertas ifupdown initramfs-tools iw kali-defaults man-db mlocate netcat-traditional net-tools parted pciutils psmisc rfkill screen snmpd snmp sudo tftp tmux unrar usbutils vim wget zerofree"
  tools="aircrack-ng crunch cewl dnsrecon dnsutils ethtool exploitdb hydra john libnfc-bin medusa metasploit-framework mfoc ncrack nmap passing-the-hash proxychains recon-ng sqlmap tcpdump theharvester tor tshark usbutils whois windows-binaries winexe wpscan wireshark"
  services="apache2 atftpd openssh-server openvpn tightvncserver"
  extras="bluez bluez-firmware i2c-tools python3-configobj python3-pip python3-requests python3-rpi.gpio python3-smbus triggerhappy wpasupplicant crda"
  desktop=""
fi
