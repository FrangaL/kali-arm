#!/usr/bin/env bash

# Calculate the space to create the image.
root_size=$(du -s -B1 "${work_dir}" --exclude="${work_dir}"/boot | cut -f1)
root_extra=$((root_size/1024/1000*5*1024/5))
raw_size=$(($((free_space*1024))+root_extra+$((bootsize*1024))+4096))
