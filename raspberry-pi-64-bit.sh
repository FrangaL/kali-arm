#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Raspberry Pi 2 1.2/3/4/400 (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/raspberry-pi-64-bit/
#

./raspberry-pi.sh --arch arm64 "$@"
