#!/usr/bin/env bash

# Debug function
function debug () {
  if [ "$debug" = true ]; then
    exec > >(tee -a -i "${0%.*}.log") 2>&1
    set -x
  fi
}; debug;

# Colors definition
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
bold=$(tput bold)
none=$(tput sgr0)

# Print color echo
function log (){
  message=$1
  color=$2
  echo -e "$color$message" $none
  sleep 0.3
  return
}

# Function to include common files
function include () {
  local file="$@"
  if [[ -f "$(dirname $0)/common.d/${file}.sh" ]]; then
    log " ✅ Load common file ${file}" ${green}
    source "$(dirname $0)/common.d/${file}.sh"
    return 0
  else
    log " ⚠️  Fail to load ${file} file" ${red}
    exit 1
  fi
}

# systemd-nspawn enviroment
function systemd-nspawn_exec (){
  systemd-nspawn -q --bind-ro ${qemu_bin} --hostname=$hostname --capability=cap_setfcap -E RUNLEVEL=1,LANG=C -M ${machine} -D ${work_dir} "$@"
}

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
function debootstrap_exec (){
  eatmydata debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --components=${components} \
    --include=kali-archive-keyring,eatmydata --arch ${architecture} ${suite} ${work_dir} "$@"
}

# Disable the use of http proxy in case it is enabled.
function disable_proxy (){
  if [ -n "$proxy_url" ]; then
    unset http_proxy
    rm -rf ${work_dir}/etc/apt/apt.conf.d/66proxy
  fi
}

# Mirror & suite replacement
function restore_mirror (){
  if [[ ! -z "${replace_mirror}" ]]; then
    mirror=${replace_mirror}
  elif [[ ! -z "${replace_suite}" ]]; then
    suite=${replace_suite}
  fi
}

# Limite use cpu function
function limit_cpu (){
  rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) # Randowm name group
  cgcreate -g cpu:/cpulimit-${rand} # Name of group cpulimit
  cgset -r cpu.shares=800 cpulimit-${rand} # Max 1024
  cgset -r cpu.cfs_quota_us=80000 cpulimit-${rand} # Max 100000
  # Retry command
  local n=1; local max=5; local delay=2
  while true; do
    cgexec -g cpu:cpulimit-${rand} "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        log "Command failed. Attempt $n/$max " ${red}
        sleep $delay;
      else
        log "The command has failed after $n attempts." ${yellow}
        break
      fi
    }
  done
}

# Choose a locale
function set_locale (){
  LOCALES="$1"
  sed -i 's/^# *\($LOCALES\)/\1/' ${work_dir}/etc/locale.gen
  systemd-nspawn_exec locale-gen
  echo LANG=$LOCALES >${work_dir}/etc/locale.conf
  echo LC_ALL=$LOCALES >>${work_dir}/etc/locale.conf
  cat <<'EOM' >${work_dir}/etc/profile.d/default-lang.sh
if [ -z "$LANG" ]; then
    source /etc/locale.conf
    export LANG
elif [ -z "$LC_ALL" ]; then
    source /etc/locale.conf
    export LC_ALL
fi
EOM
}

# Set hostname
function set_hostname (){
  if [[ $@ =~ ^[a-zA-Z0-9-]{2,63}+$ ]] ;then
    echo "$@" > ${work_dir}/etc/hostname
  else
    log "$@ is not a correct hostname" $red
    log "Using kali to default hostname" $bold
    echo "kali" > ${work_dir}/etc/hostname
  fi
}

# Add network interface
function add_interface (){
  interfaces="$@"
  for netdev in $interfaces; do
  cat << EOF > ${work_dir}/etc/network/interfaces.d/$netdev
auto $netdev
    allow-hotplug $netdev
    iface $netdev inet dhcp
EOF
  log "Configured /etc/network/interfaces.d/$netdev" $bold
  done
}

# Make SWAP
function make_swap (){
  if [ "$swap" = yes ]; then
    echo 'vm.swappiness = 50' >> ${work_dir}/etc/sysctl.conf
    systemd-nspawn_exec apt-get install -y dphys-swapfile > /dev/null 2>&1
    #sed -i 's/#CONF_SWAPSIZE=/CONF_SWAPSIZE=128/g' ${work_dir}/etc/dphys-swapfile
  fi
}

function print_config (){
  echo ""
  sleep 1
}
