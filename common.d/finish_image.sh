#!/usr/bin/env bash
#
# Every Kali ARM image finishes with this
#

# Stop on error
set -e

# Make sure we are somewhere we are not going to unmount
cd "${repo_dir}/"

# Flush buffers and bytes - this is nicked from the Devuan arm-sdk
blockdev --flushbufs "${loopdevice}"
python3 -c 'import os; os.fsync(open("'${loopdevice}'", "r+b"))'

# Unmount filesystem
status "Unmount filesystem"
[ -n "${bootp}" ] && umount -l "${bootp}" || true
umount -l "${rootp}"

# Check filesystem
status "Check filesystem partitions ($rootfstype)"
if [ -n "${bootp}" ] && [ "${extra}"  = 1 ]; then
 log "Check filesystem boot partition:$(tput sgr0) (${bootfstype})" green
 if [ "$bootfstype" = "vfat" ]; then
  dosfsck -w -r -a -t "${bootp}"
 else
  e2fsck -y -f "${bootp}"
 fi
fi

log "Check filesystem root partition:$(tput sgr0) ($rootfstype)" green
e2fsck -y -f "${rootp}"

# Remove loop devices
status "Remove loop devices"
losetup -d "${loopdevice}"

# Compress image compilation
compress_img

# Clean up all the temporary build stuff and remove the directories
clean_build

# Quit
log "\n Your image is: $(tput sgr0) $img (Size: $(du -h $img | cut -f1))" bold
exit 0
