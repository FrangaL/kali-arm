#!/usr/bin/env bash

# Disable IPv6
if [ "$disable_ipv6" = "yes" ]; then
  echo "# Don't load ipv6 by default" > ${work_dir}/etc/modprobe.d/ipv6.conf
  echo "alias net-pf-10 off" >> ${work_dir}/etc/modprobe.d/ipv6.conf
fi

cat << EOF > ${work_dir}/etc/network/interfaces
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF
