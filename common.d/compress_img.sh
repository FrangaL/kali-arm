#!/usr/bin/env bash

if [ $compress = xz ]; then
  log "Compressing ${imagename}.img" $green
  if [ $(arch) == 'x86_64' ]; then
    [ $(nproc) \< 4 ] || cpu_cores=4 # cpu_cores = Number of cores to use
    limit_cpu pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p Nº cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  else
    [ $(nproc) \< 2 ] || cpu_cores=2
    xz -T ${cpu_cores:-1} ${current_dir}/${imagename}.img # -T Nº cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  fi
else
  chmod 644 ${current_dir}/${imagename}.img
fi
