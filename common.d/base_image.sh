#!/usr/bin/env bash
#
# Every Kali ARM image starts with this
#

# shellcheck disable=SC2154
# shellcheck source=/dev/null

# Stop on error
set -e

# Load general functions
source ./common.d/functions.sh

# Read in any command line arguments
arguments $*

# Load common variables
# Needs to come after arguments, given the values are used as variables
source ./common.d/variables.sh

# If there is any issues, run check_trap (from ./common.d/functions.sh)
trap check_trap INT ERR SIGTERM SIGINT
# Always at the end, run clean_build (from ./common.d/functions.sh)
trap clean_build EXIT

# Checks script environment
source ./common.d/check.sh

# Packages build list
include packages

# Execute initial debootstrap
debootstrap_exec http://http.kali.org/kali

# Define sources.list
sources_list

# APT options
include apt_options

# Disable suspend/resume - speeds up boot massively
mkdir -p "${work_dir}/etc/initramfs-tools/conf.d/"
echo "RESUME=none" > "${work_dir}/etc/initramfs-tools/conf.d/resume"

# Copy directory bsp into build dir
status "Copy directory bsp into build dir"
cp -rp bsp "${work_dir}"

# Third stage
cat <<EOF > "${work_dir}/third-stage"
#!/usr/bin/env bash
# Stop on error
set -e

status_3i=0
status_3t=\$(grep '^status_stage3 ' \$0 | wc -l)

status_stage3() {
  status_3i=\$((status_3i+1))
  echo  "  $(tput setaf 15)✅ Stage 3 (\${status_3i}/\${status_3t}):$(tput setaf 2) \$1$(tput sgr0)"
}

status_stage3 'Update apt'
export DEBIAN_FRONTEND=noninteractive
eatmydata apt-get update

status_stage3 'Install core packages'
eatmydata apt-get -y install ${third_stage_pkgs}

status_stage3 'Install packages'
eatmydata apt-get install -y ${packages} || eatmydata apt-get install -y --fix-broken
EOF

if [ "${desktop}" != "none" ]; then
  log "Desktop mode enabled: ${desktop}" green
  cat <<EOF >> "${work_dir}/third-stage"
status_stage3 'Install desktop packages'
eatmydata apt-get install -y ${desktop_pkgs} ${extra} || eatmydata apt-get install -y --fix-broken
EOF
fi

cat <<EOF >> "${work_dir}/third-stage"
status_stage3 'ntp does not always sync the date, but systemd-timesyncd does, so we remove ntp and reinstall it with this'
eatmydata apt-get install -y systemd-timesyncd --autoremove

status_stage3 'Set various defaults in debconf'
debconf-set-selections -v << _EOF_
# Disable popularity-contest
popularity-contest popularity-contest/participate boolean false

# Disable the encfs error message
encfs encfs/security-information boolean true
encfs encfs/security-information seen true

# Random other questions
console-common console-data/keymap/policy select "Select keymap from full list"
console-common console-data/keymap/full select en-latin1-nodeadkeys
console-setup console-setup/charmap47 select UTF-8
samba-common samba-common/dhcp boolean false
kismet-capture-common kismet-capture-common/install-users string
kismet-capture-common kismet-capture-common/install-setuid boolean true
wireshark-common wireshark-common/install-setuid boolean true
sslh sslh/inetd_or_standalone select standalone
atftpd atftpd/use_inetd boolean false
_EOF_

status_stage3 'Copy all services'
cp -p /bsp/services/all/*.service /etc/systemd/system/

status_stage3 'Enable SSH service'
systemctl enable ssh

status_stage3 'Allow users to use NetworkManager over SSH'
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

status_stage3 'Copy script growpart'
install -m755 /bsp/scripts/growpart /usr/local/bin/

status_stage3 'Copy script rpi-resizerootfs'
install -m755 /bsp/scripts/rpi-resizerootfs /usr/sbin/

status_stage3 'Enable rpi-resizerootfs first boot'
systemctl enable rpi-resizerootfs

status_stage3 'Enable runonce script'
install -m755 /bsp/scripts/runonce /usr/sbin/
cp -rf /bsp/runonce.d /etc
systemctl enable runonce

# Install Powershell 7.1.3
# c0ntra reports that newer than this has issues connecting to SOC-200
status_stage3 'Install powershell 7.1.3'
if [[ ${architecture} != armel ]]; then
  if [[ ${architecture} == "arm64" ]]; then
    curl -L -o /tmp/powershell.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v7.1.3/powershell-7.1.3-linux-arm64.tar.gz
  else
    curl -L -o /tmp/powershell.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v7.1.3/powershell-7.1.3-linux-arm32.tar.gz
  fi
    mkdir -p /opt/microsoft/powershell/7
    tar -xf  /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7
    chmod +x /opt/microsoft/powershell/7/pwsh
    ln -s /opt/microsoft/powershell/7/pwsh
fi

status_stage3 'Try and make the console a bit nicer. Set the terminus font for a bit nicer display'
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

status_stage3 'Fix startup time from 5 minutes to 15 secs on raise interface'
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

status_stage3 'Mask smartmontools service'
systemctl mask smartmontools
EOF
