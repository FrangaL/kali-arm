#!/usr/bin/env bash

# Check EUID=0 you can run any binary as root.
if [[ $EUID -ne 0 ]]; then
  log "This script must be run as root or have super user permissions" red
  log "Use: $(tput sgr0)sudo $0" green
  exit 1
fi

# Check exist bsp directory.
if [ ! -e "bsp" ]; then
  log "Error: missing bsp directory structure" red
  log "Please clone the full repository ${kaligit}/build-scripts/kali-arm" green
  exit 255
fi

# Check directory build
if [ -e "${basedir}" ]; then
  log "${basedir} directory exists, will not continue" red
  exit 1
elif [[ ${current_dir} =~ [[:space:]] ]]; then
  log "The directory "\"${current_dir}"\" contains whitespace. Not supported." red
  exit 1
else
  print_config
  mkdir -p ${basedir}
fi

# Detect architecture
case ${architecture} in
  arm64)
    qemu_bin="/usr/bin/qemu-aarch64-static"
    lib_arch="aarch64-linux-gnu" ;;
  armhf)
    qemu_bin="/usr/bin/qemu-arm-static"
    lib_arch="arm-linux-gnueabihf" ;;
  armel)
    qemu_bin="/usr/bin/qemu-arm-static"
    lib_arch="arm-linux-gnueabi" ;;
esac

# Check systemd-nspawn version
nspawn_ver=$(systemd-nspawn --version | awk '{if(NR==1) print $2}')
if [[ $nspawn_ver -ge 241 ]]; then
    extra_args="-q --hostname=$hostname"
elif [[ $nspawn_ver -ge 245 ]]; then
    extra_args="-q -P --hostname=$hostname"
else
    extra_args="-q"
fi
