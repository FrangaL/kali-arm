#!/usr/bin/env bash

log "compress image" green

if [ "${compress:=}" = xz ]; then
  log "Compressing file: $(tput sgr0) ${imagename:=}.img" green
  if [ "$(arch)" == 'x86_64' ] || [ "$(arch)" == 'aarch64' ]; then
    limit_cpu pixz -p "${num_cores:=}" "${image_dir:=}"/"${imagename}".img # -p Nº cpu cores use
  else
    xz --memlimit-compress=50% -T "$num_cores" "${image_dir}"/"${imagename}".img # -T Nº cpu cores use
  fi
  chmod 0644 "${image_dir}"/"${imagename}".img.xz
else
  chmod 0644 "${image_dir}"/"${imagename}".img
fi
