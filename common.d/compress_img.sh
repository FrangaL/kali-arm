#!/usr/bin/env bash

if [ $compress = xz ]; then
  if [ $(arch) == 'x86_64' ]; then
    log "Compressing ${imagename}.img" $green
    [ $(nproc) \< 3 ] || cpu_cores=3 # cpu_cores = Number of cores to use
    limit_cpu pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p Nº cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  fi
else
  chmod 644 ${current_dir}/${imagename}.img
fi


# # Comprimir imagen
# if [[ $COMPRESS == gzip ]]; then
#   gzip "${IMGNAME}"
#   chmod 664 ${IMGNAME}.gz
# elif [[ $COMPRESS == xz ]]; then
#   [ $(nproc) \< 3 ] || CPU_CORES=4 # CPU_CORES = Número de núcleos a usar
#   xz -T ${CPU_CORES:-2} "${IMGNAME}"
#   chmod 664 ${IMGNAME}.xz
# fi
