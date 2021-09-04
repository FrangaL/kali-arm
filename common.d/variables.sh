#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154

# Generate a random machine name to be used.
machine=$(dbus-uuidgen)
# Version Kali release
version=${version:-$(cat .release)}
# Custom hostname variable
hostname=${hostname:-kali}
# Suite to use, valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
suite=${suite:-"kali-rolling"}
# Choose a locale
locale="en_US.UTF-8"
# Free space rootfs in MiB
free_space="300"
# /boot partition in MiB
bootsize="128"
# Select compression, xz or none
compress="xz"
# Choose filesystem format to format ( ext3 or ext4 )
fstype="ext3"
# Generate a random root partition UUID to be used.
root_uuid=$(cat </proc/sys/kernel/random/uuid | less)
# Disable IPV6 ( yes or no)
disable_ipv6="yes"
# Make SWAP ( yes or no)
swap="no"
# Use 0 for unlimited CPU cores, -1 to subtract 1 cores from the total
cpu_cores="4"
# 0 or 100 No limit, 10 = percentage use, 50, 75, 90, etc.
cpu_limit="85"
# If you have your own preferred mirrors, set them here.
mirror=${mirror:-"http://http.kali.org/kali"}
# Use packages from the listed components of the archive.
components="main,contrib,non-free"
# Gitlab url Kali repository
kaligit="https://gitlab.com/kalilinux"
# Github raw url
githubraw="https://raw.githubusercontent.com"
# Current directory
current_dir="$(pwd)"
# Base directory
basedir=${current_dir}/${hw_model}-${variant}
# Working directory
work_dir="${basedir}/kali-${architecture}"
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${imagename:-"kali-linux-${version}-${hw_model}-${variant}"}
# workaround for LP: #520465
export MALLOC_CHECK_=0
# Proxy
# You can turn off automatic settings by uncommenting apt_cacher=off.
# apt_cacher=off
# By default the proxy settings are local, but you can define an external proxy.
# proxy_url="http://external.intranet.local"

# Load build configuration
if [ -f "${current_dir}"/builder.txt ]; then
  # shellcheck source=/dev/null
  source "${current_dir}"/builder.txt
fi
