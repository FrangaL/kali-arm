#!/usr/bin/env bash

set -e

# includes files from workdir
log "Include files on kali-config/common/includes.chroot" green

if [[ "${debug}" == "true" ]]
then
  cp_debug_flag="-v"
fi

cp -r ${cp_debug_flag} kali-config/common/includes.chroot/* "${work_dir}"/
[[ -d  "kali-config/variant-${desktop}/includes.chroot" ]] && cp -r ${cp_debug_flag} kali-config/variant-"${desktop}"/includes.chroot/* "${work_dir}"/
