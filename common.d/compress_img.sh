#!/usr/bin/env bash

if [ "${compress:=}" = xz ]; then
  log "Compressing file: $(tput sgr0) ${imagename:=}.img" green
  if [ "$(arch)" == 'x86_64' ]; then
    limit_cpu pixz -p "${num_cores:=}" "${current_dir:=}"/"${imagename}".img # -p Nº cpu cores use
    chmod 644 "${current_dir}"/"${imagename}".img.xz
  else
    xz --memlimit-compress=50% -T "$num_cores" "${current_dir}"/"${imagename}".img # -T Nº cpu cores use
    chmod 644 "${current_dir}"/"${imagename}".img.xz
  fi
else
  chmod 644 "${current_dir}"/"${imagename}".img
fi
