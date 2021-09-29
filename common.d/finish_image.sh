#!/usr/bin/env bash
#
# Every Kali ARM image finishes with this
#

# Stop on error
set -e

# Say where we are
log "finish_image" green

# Make sure we are somewhere we are not going to unmount
cd "${current_dir}/"

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk
blockdev --flushbufs "${loopdevice}"
python3 -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Unmount filesystem
status "Unmount filesystem"
[ -n "${bootp}" ] \
  && umount -l "${bootp}" \
  || true
umount -l "${rootp}"

# Check filesystem
if [ -n "${bootp}" ] && [ "${debug}" = 1 ]; then
  status "Check filesystem (dosfsck)"
  dosfsck -w -r -a -t "${bootp}"
fi

if [ -n "${bootp}" ] && [ "${debug}"  = 1 ]; then
 fstype=$(blkid -o export "${bootp}" | grep '^TYPE' | cut -d"=" -f2)
 status "Check filesystem (dosfsck ${fstype})"
 if [ "$fstype" = "vfat" ]; then
  dosfsck -w -r -a -t "${bootp}"
 else
  e2fsck -y -f "${bootp}"
 fi
fi

status "Check filesystem (e2fsck)"
e2fsck -y -f "${rootp}"

# Remove loop devices
status "Remove loop devices"
kpartx -dsv "${loopdevice}"
losetup -d "${loopdevice}"

# Compress image compilation
include compress_img

# Clean up all the temporary build stuff and remove the directories
clean_build

# Quit
log "Done" green
exit 0
