#!/usr/bin/env bash

# Clean system
systemd-nspawn_exec <<'EOF'
rm -f /0
rm -rf /bsp
fc-cache -frs
rm -rf /tmp/*
rm -rf /etc/*-
rm -rf /hs_err*
rm -rf /userland
rm -rf /opt/vc/src
rm -rf /third-stage
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/dpkg/*-old
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin
rm -rf /var/cache/debconf/*-old
rm -rf /var/cache/apt/archives/*
rm -rf /etc/apt/apt.conf.d/apt_opts
rm -rf /etc/apt/apt.conf.d/99_norecommends
find /var/log -depth -type f -print0 | xargs -0 truncate -s 0
history -c
EOF
