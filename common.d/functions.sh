#!/usr/bin/env bash
# shellcheck disable=SC2154

# Print color echo
function log() {
    local set_color="$2"

    case $set_color in
        bold)
            color=$(tput bold) ;;

        red)
            color=$(tput setaf 1) ;;

        green)
            color=$(tput setaf 2) ;;

        yellow)
            color=$(tput setaf 3) ;;

        cyan)
            color=$(tput setaf 6) ;;

        gray)
            color=$(tput setaf 8) ;;

        white)
            color=$(tput setaf 15) ;;

        *)
            text="$1" ;;

    esac

    ## --no-color
    if [ "$colour_output" == "no" ]; then
        echo -e "$1"

    elif [ -z "$text" ]; then
        echo -e "$color $1 $(tput sgr0)"

    else
        echo -e "$text"

    fi
}

# Usage function
function usage() {
    log "Usage commands:" bold

    cat <<EOF
    # Architectures (arm64, armel, armhf)
    $0 --arch arm64 or $0 -a armhf

    # Desktop manager (xfce, gnome, kde, i3, lxde, mate, e17 or none)
    $0 --desktop kde or $0 --desktop=kde

    # Minimal image - no desktop manager (alias to --desktop=none)
    $0 --minimal or $0 -m

    # Slim image - no desktop manager & no Kali tools
    $0 --slim or $0 -s

    # Enable debug & log file (./logs/<file>.log)
    $0 --debug or $0 -d

    # Perform extra checks on the images build
    $0 --extra or $0 -x

    # Remove color from output
    $0 --no-color or $0 --no-colour

    # Help screen (this)
    $0 --help or $0 -h
EOF

    exit 0
}

# Debug function
function debug_enable() {
    log="./logs/${0%.*}-$(date +"%Y-%m-%d-%H-%M").log"
    mkdir -p ./logs/
    log "Debug: Enabled" green
    log "Output: ${log}" green
    exec &> >(tee -a "${log}") 2>&1

    # Print all commands inside of script
    set -x
    debug=1
    extra=1
}

# Validate desktop
function validate_desktop() {
    case $1 in
        xfce | gnome | kde | i3 | lxde | mate | e17)
            true ;;

        none)
            variant="minimal" ;;

        *)
            log "\n ⚠️  Unknown desktop:$(tput sgr0) $1\n" red; usage ;;

    esac
}

# Arguments function
function arguments() {
    while [[ $# -gt 0 ]]; do
        opt="$1"

        shift

        case "$(echo ${opt} | tr '[:upper:]' '[:lower:]')" in
            "--")
                break 2 ;;

            -a | --arch)
                architecture="$1"; shift ;;

            --arch=*)
                architecture="${opt#*=}" ;;

            --desktop)
                validate_desktop $1; desktop="$1"; shift ;;

            --desktop=*)
                validate_desktop "${opt#*=}"; desktop="${opt#*=}" ;;

            -m | --minimal)
                variant="minimal"; minimal="1"; desktop="minimal" ;;

            -s | --slim)
                variant="slim"; desktop="slim"; minimal="1"; slim="1" ;;

            -d | --debug)
                debug_enable ;;

            -x | --extra)
                log "Extra Checks: Enabled" green; extra="1" ;;

            --no-color | --no-colour)
                colour_output="no" ;;

            -h | -help | --help)
                usage ;;

            *)
                log "Unknown option: ${opt}" red; exit 1 ;;

        esac
    done
}

# Function to include common files
function include() {
    local file="$1"

    if [[ -f "common.d/${file}.sh" ]]; then
        log " ✅ Load common file:$(tput sgr0) ${file}" green

        # shellcheck source=/dev/null
        source "common.d/${file}.sh" "$@"
        return 0

    else
        log " ⚠️  Fail to load ${file} file" red

        [ "${debug}" = 1 ] && pwd || true

        exit 1

    fi
}

# systemd-nspawn environment
# Putting quotes around $extra_args causes systemd-nspawn to pass the extra arguments as 1, so leave it unquoted.
function systemd-nspawn_exec() {
    log "systemd-nspawn $*" gray
    ENV="RUNLEVEL=1,LANG=C,DEBIAN_FRONTEND=noninteractive,DEBCONF_NOWARNINGS=yes"

    if [ "$(arch)" != "aarch64" ]; then
        systemd-nspawn --bind-ro "$qemu_bin" $extra_args --capability=cap_setfcap -E $ENV -M "$machine" -D "$work_dir" "$@"
    else
        systemd-nspawn $extra_args --capability=cap_setfcap -E $ENV -M "$machine" -D "$work_dir" "$@"
    fi
}

# Create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
function debootstrap_exec() {
    status " debootstrap ${suite} $*"

    if [ "$(lsb_release -sc)" == "bullseye" ]; then
    eatmydata debootstrap --merged-usr --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --components="${components}" \
        --include="${debootstrap_base}" --arch "${architecture}" "${suite}" "${work_dir}" "$@"
    else
    eatmydata mmdebstrap --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --components="${components}" \
        --include="${debootstrap_base}" --arch "${architecture}" "${suite}" "${work_dir}" "$@"
    fi
}

# Disable the use of http proxy in case it is enabled.
function disable_proxy() {
    if [ -n "$proxy_url" ]; then
        log "Disable proxy" gray
        unset http_proxy
        rm -rf "${work_dir}"/etc/apt/apt.conf.d/66proxy

    elif [ "${debug}" = 1 ]; then
        log "Proxy enabled" yellow

    fi
}

# Mirror & suite replacement
function restore_mirror() {
    if [[ -n "${replace_mirror}" ]]; then
        export mirror=${replace_mirror}

    elif [[ -n "${replace_suite}" ]]; then
        export suite=${replace_suite}

    fi

    log "Mirror & suite replacement" gray

    # For now, restore_mirror will put the default kali mirror in, fix after 2021.3
    cat <<EOF >"${work_dir}"/etc/apt/sources.list
# See https://www.kali.org/docs/general-use/kali-linux-sources-list-repositories/
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware

# Additional line for source packages
# deb-src http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF
}

# Limit CPU function
function limit_cpu() {
    if [[ ${cpu_limit:=} -lt "1" ]]; then
        cpu_limit=-1
        log "CPU limiting has been disabled" yellow
        eval "${@}"

        return $?

    elif [[ ${cpu_limit:=} -gt "100" ]]; then
        log "CPU limit (${cpu_limit}) is higher than 100" yellow
        cpu_limit=100

    fi

    if [[ -z $cpu_limit ]]; then
        log "CPU limit unset" yellow
        local cpu_shares=$((num_cores * 1024))
        local cpu_quota="-1"

    else
        log "Limiting CPU (${cpu_limit}%)" yellow
        local cpu_shares=$((1024 * num_cores * cpu_limit / 100))  # 1024 max value per core
        local cpu_quota=$((100000 * num_cores * cpu_limit / 100)) # 100000 max value per core

    fi

    # Random group name
    local rand
    rand=$(
        tr -cd 'A-Za-z0-9' </dev/urandom | head -c4
        echo
    )

    cgcreate -g cpu:/cpulimit-"$rand"
    cgset -r cpu.shares="$cpu_shares" cpulimit-"$rand"
    cgset -r cpu.cfs_quota_us="$cpu_quota" cpulimit-"$rand"

    # Retry command
    local n=1
    local max=5
    local delay=2

    while true; do
        # shellcheck disable=SC2015
        cgexec -g cpu:cpulimit-"$rand" "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                log "Command failed. Attempt $n/$max" red
                sleep $delay

            else
                log "The command has failed after $n attempts" yellow
                break

            fi
        }

    done

    cgdelete -g cpu:/cpulimit-"$rand"
}

function sources_list() {
    # Define sources.list
    log " ✅ define sources.list" green
    cat <<EOF >"${work_dir}"/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF
}

# Choose a locale
function set_locale() {
    LOCALES="$1"

    log "locale:$(tput sgr0) ${LOCALES}" gray
    sed -i "s/^# *\($LOCALES\)/\1/" "${work_dir}"/etc/locale.gen

    #systemd-nspawn_exec locale-gen
    echo "LANG=$LOCALES" >"${work_dir}"/etc/locale.conf
    echo "LC_ALL=$LOCALES" >>"${work_dir}"/etc/locale.conf

    cat <<'EOM' >"${work_dir}"/etc/profile.d/default-lang.sh
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
function set_hostname() {
    if [[ "$1" =~ ^[a-zA-Z0-9-]{2,63}+$ ]]; then
        log " Created /etc/hostname" white
        echo "$1" >"${work_dir}"/etc/hostname

    else
        log "$1 is not a correct hostname" red
        log "Using kali to default hostname" bold
        echo "kali" >"${work_dir}"/etc/hostname

    fi
}

# Add network interface
function add_interface() {
    interfaces="$*"
    for netdev in $interfaces; do
        cat <<EOF >"${work_dir}"/etc/network/interfaces.d/"$netdev"
auto $netdev
    allow-hotplug $netdev
    iface $netdev inet dhcp
EOF

        log " Configured /etc/network/interfaces.d/$netdev" white

    done
}

function basic_network() {
    # Disable IPv6
    if [ "$disable_ipv6" = "yes" ]; then
        log " Disable IPv6" white

        echo "# Don't load ipv6 by default" >"${work_dir}"/etc/modprobe.d/ipv6.conf
        echo "alias net-pf-10 off" >>"${work_dir}"/etc/modprobe.d/ipv6.conf
    fi

    cat <<EOF >"${work_dir}"/etc/network/interfaces
source-directory /etc/network/interfaces.d

auto lo
  iface lo inet loopback

EOF
    make_hosts
}

function make_hosts() {
    set_hostname "${hostname}"

    log " Created /etc/hosts" white
    cat <<EOF >"${work_dir}"/etc/hosts
127.0.1.1       ${hostname:=}
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
}

# Make SWAP
function make_swap() {
    if [ "$swap" = yes ]; then
        log "Make swap" green
        echo 'vm.swappiness = 50' >>"${work_dir}"/etc/sysctl.conf

        #sed -i 's/#CONF_SWAPSIZE=/CONF_SWAPSIZE=128/g' ${work_dir}/etc/dphys-swapfile

    else
        [[ -f ${work_dir}/swapfile.img ]] || log "Make Swap:$(tput sgr0) Disabled" yellow

    fi
}

# Print current config.
function print_config() {
    log "\n Compilation info" bold
    name_model="$(sed -n '3'p $0)"

    log "Hardware model: $(tput sgr0)${name_model#* for}" cyan
    log "Architecture: $(tput sgr0)$architecture" cyan
    log "OS build: $(tput sgr0)$suite $version" cyan
    log "Desktop manager: $(tput sgr0)$desktop" cyan
    log "The base_dir thinks it is: $(tput sgr0)${base_dir}\n" cyan

    sleep 1.5
}

# Calculate the space to create the image and create.
function make_image() {
    # Calculate the space to create the image.
    root_size=$(du -s -B1 "${work_dir}" --exclude="${work_dir}"/boot | cut -f1)
    root_extra=$((root_size * 5 * 1024 / 5 / 1024 / 1000))
    raw_size=$(($((free_space * 1024)) + root_extra + $((bootsize * 1024)) + 4096))
    img_size=$(echo "${raw_size}"Ki | numfmt --from=iec-i --to=si)

    # Create the disk image
    log "Creating image file:$(tput sgr0) ${image_name}.img (Size: ${img_size})" white
    [ -d ${image_dir} ] || mkdir -p "${image_dir}/"
    fallocate -l "${img_size}" "${image_dir}/${image_name}.img"
}

# Set the partition variables
function make_loop() {
    img="${image_dir}/${image_name}.img"
    num_parts=$(fdisk -l $img | grep "${img}[1-2]" | wc -l)

    if [ "$num_parts" = "2" ]; then
        extra=1
        part_type1=$(fdisk -l $img | grep ${img}1 | awk '{print $6}')
        part_type2=$(fdisk -l $img | grep ${img}2 | awk '{print $6}')

        if [[ "$part_type1" == "c" ]]; then
            bootfstype="vfat"

        elif [[ "$part_type1" == "83" ]]; then
            bootfstype=${bootfstype:-"$fstype"}

        fi

        rootfstype=${rootfstype:-"$fstype"}
        loopdevice=$(losetup --show -fP "$img")
        bootp="${loopdevice}p1"
        rootp="${loopdevice}p2"

    elif [ "$num_parts" = "1" ]; then
        part_type1=$(fdisk -l $img | grep ${img}1 | awk '{print $6}')

        if [[ "$part_type1" == "83" ]]; then
            rootfstype=${rootfstype:-"$fstype"}

        fi

        rootfstype=${rootfstype:-"$fstype"}
        loopdevice=$(losetup --show -fP "$img")
        rootp="${loopdevice}p1"

    fi
}

# Create fstab file.
function make_fstab() {
    status "Create /etc/fstab"
    cat <<EOF >"${work_dir}"/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0

UUID=$root_uuid /               $rootfstype errors=remount-ro 0       1
EOF

    if ! [ -z "$bootp" ]; then
        echo "LABEL=BOOT      /boot           $bootfstype    defaults          0       2" >>"${work_dir}"/etc/fstab

    fi

    make_swap

    if [ -f "${work_dir}/swapfile.img" ]; then
        cat <<EOF >>${work_dir}/etc/fstab
/swapfile.img   none            swap    sw                0       0
EOF

    fi
}

# Create file systems
function mkfs_partitions() {
    status "Formatting partitions"
    # Formatting boot partition.
    if [ -n "${bootp}" ]; then
        case $bootfstype in
            vfat)
                mkfs.vfat -n BOOT -F 32 "${bootp}" ;;

            ext4)
                features="^64bit,^metadata_csum"; 
                mkfs -O "$features" -t "$fstype" -L BOOT "${bootp}" ;;

            ext2 | ext3)
                features="^64bit"
                mkfs -O "$features" -t "$fstype" -L BOOT "${bootp}" ;;

        esac

        bootfstype=$(blkid -o value -s TYPE $bootp)

    fi

    # Formatting root partition.
    if [ -n "${rootp}" ]; then
        case $rootfstype in
            ext4)
                features="^64bit,^metadata_csum" ;;

            ext2 | ext3)
                features="^64bit" ;;

        esac

        yes | mkfs -U "$root_uuid" -O "$features" -t "$fstype" -L ROOTFS "${rootp}"
        root_partuuid=$(blkid -s PARTUUID -o value ${rootp})
        rootfstype=$(blkid -o value -s TYPE $rootp)

    fi
}

# Compress image compilation
function compress_img() {
    if [ "${compress:=}" = xz ]; then
        status "Compressing file: ${image_name}.img"

        if [ "$(arch)" == 'x86_64' ] || [ "$(arch)" == 'aarch64' ]; then
            limit_cpu pixz -p "${num_cores:=}" "${image_dir}/${image_name}.img" # -p Nº cpu cores use

        else
            xz --memlimit-compress=50% -T "$num_cores" "${image_dir}/${image_name}.img" # -T Nº cpu cores use

        fi

        img="${image_dir}/${image_name}.img.xz"

    fi

    chmod 0644 "$img"
}

# Calculate total time compilation.
function fmt_plural() {
  [[ $1 -gt 1 ]] && printf "%d %s" $1 "${3}" || printf "%d %s" $1 "${2}"
}

function total_time() {
  local t=$(( $1 ))
  local h=$(( t / 3600 ))
  local m=$(( t % 3600 / 60 ))
  local s=$(( t % 60 ))

  printf "\nFinal time: "
  [[ $h -gt 0 ]] && { fmt_plural $h "hour" "hours"; printf " "; }
  [[ $m -gt 0 ]] && { fmt_plural $m "minute" "minutes"; printf " "; }
  [[ $s -gt 0 ]] && fmt_plural $s "second" "seconds"
  printf "\n"
}

function umount_partitions() {
    # Make sure we are somewhere we are not going to unmount
    cd "${repo_dir}/"

    # Unmount filesystem
    log "Unmount filesystem..." green

    # If there is boot partition, unmount that first. Else continue as not every ARM device has one
    [ -n "${bootp}" ] &&
        ! mountpoint -q "${base_dir}/root/boot" || umount -q "${base_dir}/root/boot" ||
        true

    ! mountpoint -q "${base_dir}/root" || umount -q "${base_dir}/root"
}

# Clean up all the temporary build stuff and remove the directories.
function clean_build() {
    log "Cleaning up" green

    # unmount anything that may be mounted
    umount_partitions

    # Delete files
    log "Cleaning up the temporary build files..." green
    rm -rf "${work_dir}"
    rm -rf "${base_dir}"

    # Done
    log "Done" green
    total_time $SECONDS
}

function check_trap() {
    log "\n ⚠️  An error has occurred!\n" red
    clean_build

    exit 1
}

# Show progress
status() {
    status_i=$((status_i + 1))
    [[ $debug = 1 ]] && timestamp="($(date +"%Y-%m-%d %H:%M:%S"))" || timestamp=""
    log " ✅ ${status_i}/${status_t}:$(tput sgr0) $1 $timestamp" green
}
