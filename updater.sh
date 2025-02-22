#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2086,SC2320

# Basic semi-automatic update/upgrade script
# Made by Jiab77 / 2022 - 2025
#
# Supported distro:
# - Debian / Ubuntu
# - RHEL / CentOS / Rocky Linux
# - Arch Linux / CachyOS
# - Termux (experimental)
#
# This version contains an experimental features:
# - ZFS Snapshots
# - FlatPak support
#
# Breaking changes:
# - As of version 0.8.0, you must use 'sudo' except for Termux.
# - As of version 0.8.2, you NO LONGER NEED TO use 'sudo'.
#
# Version 0.8.2

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

# Colors
NC="\033[0m"
NL="\n"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
WHITE="\033[1;37m"
PURPLE="\033[1;35m"

# Config
USE_PARU=true                # Only for Arch Linux based distros
ENABLE_FLATPAK=true
ENABLE_ZFS_SNAPSHOTS=true    # For ZFS only
CREATE_SNAPSHOT_FILE=false   # Create ZFS snapshot files

# Internals
BIN_FLATPAK=$(command -v flatpak 2>/dev/null)
BIN_ZFS=$(command -v zfs-snap-mgr 2>/dev/null)

# Overrides
[[ -z $BIN_FLATPAK ]] && ENABLE_FLATPAK=false
[[ -z $BIN_ZFS ]] && ENABLE_ZFS_SNAPSHOTS=false

# Functions
function get_version() {
    grep -m1 "# Version" $0 | awk '{ print $3 }'
}
function die() {
    echo -e "${NL}${WHITE}Error: ${RED}$*${NC}${NL}" >&2
    exit 255
}
function print_usage() {
    echo -e "${NL}Usage: $(basename "$0") [flags] - Automatically download and install latest updates."
    echo -e "${NL}Flags:"
    echo -e "  -h | --help\t\tPrint this message and exit"
    echo -e "  -v | --version\tPrint version and exit"
    echo
    exit
}
function print_version() {
  echo -e "\nVersion: $(get_version)\n"
  exit
}
function get_std_user() {
  # No longer assuming that standard user has UID 1000
  if [[ $(printenv | grep -ci "sudo") -ne 0 ]]; then
    echo -n $SUDO_USER
  else
    echo -n $EUID
  fi
}
function create_pre_update_snapshot() {
    if [[ $ENABLE_ZFS_SNAPSHOTS == true && ! -r /tmp/.before-update-snapshot-done ]]; then
        echo -e "${NL}${YELLOW}Making a snapshot of the system before updating...${NC}${NL}"
        sudo zfs-snap-mgr create --debug --recursive --name="before-update" --no-header && touch /tmp/.before-update-snapshot-done

        if [[ $CREATE_SNAPSHOT_FILE == true ]]; then
            echo -e "${NL}${YELLOW}Writing snapshot file...${NC}${NL}"
            sudo zfs-snap-mgr send --debug --recursive --incremental --no-header
        fi
    fi
}
function create_post_update_snapshot() {
    if [[ $ENABLE_ZFS_SNAPSHOTS == true && ! -r /tmp/.after-update-snapshot-done ]]; then
        echo -e "${NL}${YELLOW}Making a snapshot of the system after updating...${NC}${NL}"
        sudo zfs-snap-mgr create --debug --recursive --name="after-update" --no-header && touch /tmp/.after-update-snapshot-done

        if [[ $CREATE_SNAPSHOT_FILE == true ]]; then
            echo -e "${NL}${YELLOW}Writing snapshot file...${NC}${NL}"
            sudo zfs-snap-mgr send --debug --recursive --incremental --no-header
        fi
    fi
}
function update_flatpak() {
    if [[ $ENABLE_FLATPAK == true ]]; then
        echo -e "${NL}${BLUE}Updating FlatPak installed applications...${NC}${NL}"
        # sudo -u $STD_USER $BIN_FLATPAK update -y
        $BIN_FLATPAK update -y
    fi
}
function update_ubuntu() {
    BIN=$(command -v apt 2>/dev/null)
    [[ -z $BIN ]] && die "You must have 'apt' installed to run this script."

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    sudo $BIN update --fix-missing -y

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    $BIN list --upgradable

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done

    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    sudo $BIN dist-upgrade -y --allow-downgrades

    echo -e "${NL}${BLUE}Removing old packages...${NC}${NL}"
    sudo $BIN autoremove --purge -y
}
function update_redhat() {
    BIN_DNF=$(command -v dnf 2>/dev/null)
    BIN_YUM=$(command -v yum 2>/dev/null)
    [[ -z $BIN_DNF && -n $BIN_YUM ]] && BIN=$BIN_YUM || BIN=$BIN_DNF
    [[ -z $BIN ]] && die "You must have at least 'yum' or 'dnf' installed to run this script."

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    sudo $BIN makecache

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    sudo $BIN check-update

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done

    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    sudo $BIN update -y
}
function update_archlinux() {
    BIN_PARU=$(command -v paru 2>/dev/null)
    BIN_PACMAN=$(command -v pacman 2>/dev/null)
    [[ -z $BIN_PARU || $USE_PARU == false ]] && BIN=$BIN_PACMAN || BIN=$BIN_PARU
    [[ -z $BIN ]] && die "You must have at least 'pacman' or 'paru' installed to run this script."

    echo -e "${NL}${BLUE}Cleaning package cache...${NC}"
    if [[ $USE_PARU == true ]]; then
        # sudo -u $STD_USER $BIN -Scc --color always --noconfirm
        $BIN -Scc --color always --noconfirm
    else
        sudo $BIN -Scc --color always --noconfirm
    fi

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        # sudo -u $STD_USER $BIN -Sy --color always
        $BIN -Sy --color always
    else
        sudo $BIN -Sy --color always
    fi

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        # sudo -u $STD_USER $BIN -Qu --color always
        $BIN -Qu --color always
    else
        sudo $BIN -Qu --color always
    fi
    RET_CODE_CHECK=$?

    if [[ $RET_CODE_CHECK -ne 0 ]]; then
        echo -e "${NL}User cancelled update process, leaving...${NL}"
        exit $RET_CODE_CHECK
    fi

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done

    create_pre_update_snapshot

    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        # sudo -u $STD_USER $BIN -Syuu --color always --noconfirm
        $BIN -Syuu --color always --noconfirm
    else
        sudo $BIN -Syuu --color always --noconfirm
    fi
    RET_CODE_UPDATE=$?

    if [[ $RET_CODE_UPDATE -ne 0 ]]; then
        echo -e "${NL}${YELLOW}Something wrong happened, retrying with confirmations enabled...${NC}${NL}"
        if [[ $USE_PARU == true ]]; then
            # sudo -u $STD_USER $BIN -Syuu --color always
            $BIN -Syuu --color always
        else
            sudo $BIN -Syuu --color always
        fi
        RET_CODE_UPDATE_RETRY=$?
    fi

    if [[ $RET_CODE_UPDATE_RETRY -ne 0 ]]; then
        die "Something is blocking the update process, please run it manually."
    fi

    update_flatpak

    create_post_update_snapshot
}
function update_termux() {
    BIN=$(command -v apt 2>/dev/null)
    [[ -z $BIN ]] && die "You must have 'apt' installed to run this script."

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    pkg update -y

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    $BIN list --upgradable

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done

    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    pkg upgrade -y

    echo -e "${NL}${BLUE}Removing old packages...${NC}${NL}"
    $BIN autoremove --purge -y

    echo -e "${NL}${BLUE}Cleaning packages cache...${NC}${NL}"
    pkg autoclean
}
function check_reboot() {
    # Check if reboot is required
    echo -e "${NL}${BLUE}Checking if reboot is required...${NC}${NL}"

    # Select proper reboot check
    case $DISTRO in
        "debian"|"ubuntu"|"ubuntu debian")
            # Reboot test for debian / ubuntu based hosts
            if [[ -s /var/run/reboot-required ]]; then
                cat /var/run/reboot-required
            # Reboot test for pop_os
            elif [[ -r /var/run/reboot-required && $(wc -l < /var/run/reboot-required) -eq 0 ]]; then
                echo -e "${YELLOW}** Reboot required **${NC}${NL}"
            else
                echo -e "${WHITE}Nothing to do.${NC}${NL}" ; exit 0
            fi
        ;;
        "redhat"|"rhel fedora"|"rhel centos fedora"|"rancheros")
            # Reboot test for redhat based hosts
            if [[ -n $(command -v needs-restarting 2>/dev/null) ]]; then
                needs-restarting -r
            else
                echo -e "${WHITE}Nothing to do.${NC}${NL}" ; exit 0
            fi
        ;;
        "arch"|"cachyos")
            # Reboot test for archlinux based hosts
            if [[ $(pacman -Q linux-cachyos 2>/dev/null | cut -d " " -f 2) > $(uname -r | sed -e 's/-cachyos//') ]]; then
                echo -e "${YELLOW}** Reboot required **${NC}${NL}"
            else
                echo -e "${WHITE}Nothing to do.${NC}${NL}" ; exit 0
            fi
        ;;
        "termux")
            echo -e "${YELLOW}** Running on mobile phone **${NC}${NL}${YELLOW}Relaunch the app should be enough.${NC}${NL}"
        ;;
        *) die "Unable to find proper reboot check for '${WHITE}${DISTRO}${RED}'." ;;
    esac
}
function init_update() {
    # Get running user name
    STD_USER="$(get_std_user)"

    # Show machine hostname
    echo -e "${NL}${WHITE}Running on ${GREEN}$(hostname -f)${WHITE}...${NC}"

    # Show detected system
    echo -e "${NL}${WHITE}Operating System: ${YELLOW}${PRETTY_NAME}${WHITE}${NC}"

    # Select proper function
    case $DISTRO in
        "debian"|"ubuntu"|"ubuntu debian")
            update_ubuntu
            update_flatpak
            check_reboot
        ;;
        "redhat"|"rhel fedora"|"rhel centos fedora"|"rancheros")
            update_redhat
            update_flatpak
            check_reboot
        ;;
        "arch"|"cachyos")
            update_archlinux
            check_reboot
        ;;
        "termux")
            update_termux
        ;;
        *) die "OS '${WHITE}${DISTRO}${RED}' not supported." ;;
    esac
}

# OS-Release
[[ -r /etc/os-release ]] && source /etc/os-release

# Fix empty 'DISTRO' variable
if [[ -n $ID_LIKE ]]; then
    DISTRO=$ID_LIKE
else
    DISTRO=$ID
fi

# Add 'termux' support
if [[ -z $DISTRO && $(printenv | grep -ci "termux") -ne 0 ]]; then
    DISTRO="termux"
    PRETTY_NAME="Termux"
fi

# Script header
echo -e "${NL}${BLUE}Basic ${PURPLE}${PRETTY_NAME}${BLUE} semi-automatic update/upgrade script - ${GREEN}v$(get_version)${NC}"

# Args
[[ $1 == "-h" || $1 == "--help" ]] && print_usage
[[ $1 == "-v" || $1 == "--version" ]] && print_version

# Checks
[[ $# -gt 1 ]] && die "Too many arguments."
[[ -z $DISTRO ]] && die "Unable to detect your operating system."
# if [[ ! $DISTRO == "termux" ]]; then
#     [[ $(id -u) -ne 0 ]] && die "You must run this script as root or with '${YELLOW}sudo${RED}'."
# fi

# Main
init_update
