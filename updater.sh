#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2086

# Basic Ubuntu/CentOS/RockyLinux/ArchLinux semi-automatic update/upgrade script
# Made by Jiab77 / 2022 - 2023
#
# This version contains an experimental ZFS snapshot feature.
#
# Version 0.6.3

# Options
set +o xtrace

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
USE_PARU=true # Only for Arch Linux based distros
ENABLE_ZFS_SNAPSHOTS=true
CREATE_SNAPSHOT_FILE=true
BIN_ZFS=$(which zfs-snap-mgr 2>/dev/null)

# Overrides
[[ -z $BIN_ZFS ]] && ENABLE_ZFS_SNAPSHOTS=false

# Functions
get_version() {
    grep "# Version" $0 | grep -v grep | awk '{ print $3 }'
}
update_ubuntu() {
    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    sudo apt update --fix-missing -y

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    apt list --upgradable

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done
    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    sudo apt dist-upgrade -y --allow-downgrades

    echo -e "${NL}${BLUE}Removing old packages...${NC}${NL}"
    sudo apt autoremove --purge -y
}
update_redhat() {
    BIN=$(which dnf 2>/dev/null)
    [[ $BIN == "" ]] && BIN=$(which yum 2>/dev/null)
    [[ $BIN == "" ]] && echo -e "${NL}${RED}Missing yum/dnf binary.${NC}${NL}" && exit 1

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    sudo $BIN makecache

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    sudo $BIN check-update

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done
    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    sudo $BIN update -y
}
update_archlinux() {
    [[ $USE_PARU == true ]] && BIN=$(which paru 2>/dev/null)
    [[ $USE_PARU == false ]] && BIN=$(which pacman 2>/dev/null)
    [[ -z $BIN ]] && echo -e "${NL}${RED}Missing pacman or paru binary.${NC}${NL}" && exit 1

    echo -e "${NL}${BLUE}Cleaning package cache...${NC}"
    sudo $BIN -Scc --color always --noconfirm

    echo -e "${NL}${BLUE}Refresh package cache...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        $BIN -Sy --color always
    else
        sudo $BIN -Sy --color always
    fi

    echo -e "${NL}${BLUE}Display available updates...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        $BIN -Qu --color always
    else
        sudo $BIN -Qu --color always
    fi
    RET_CODE_CHECK=$?
    if [[ $RET_CODE_CHECK -ne 0 ]]; then
        echo -e "\nUser cancelled update process, leaving...\n"
        exit $RET_CODE_CHECK
    fi

    echo -e "${NL}${BLUE}Initializing update process...${NC}${NL}"
    for I in {5..1} ; do echo "Start in $I seconds..." ; sleep 1 ; done

    if [[ $ENABLE_ZFS_SNAPSHOTS == true ]]; then
        echo -e "${NL}${YELLOW}Making a snapshot of the system before updating...${NC}${NL}"
        sudo zfs-snap-mgr create --debug --recursive --name="before-update" --no-header

        if [[ $CREATE_SNAPSHOT_FILE == true ]]; then
            echo -e "${NL}${YELLOW}Writing snapshot file...${NC}${NL}"
            sudo zfs-snap-mgr send --debug --recursive --incremental --no-header
        fi
    fi

    echo -e "${NL}${BLUE}Applying updates...${NC}${NL}"
    if [[ $USE_PARU == true ]]; then
        $BIN -Syuu --color always --noconfirm
    else
        sudo $BIN -Syuu --color always --noconfirm
    fi

    if [[ $ENABLE_ZFS_SNAPSHOTS == true ]]; then
        echo -e "${NL}${YELLOW}Making a snapshot of the system after updating...${NC}${NL}"
        sudo zfs-snap-mgr create --debug --recursive --name="after-update" --no-header

        if [[ $CREATE_SNAPSHOT_FILE == true ]]; then
            echo -e "${NL}${YELLOW}Writing snapshot file...${NC}${NL}"
            sudo zfs-snap-mgr send --debug --recursive --incremental --no-header
        fi
    fi
}
check_reboot() {
    # Check if reboot is required
    echo -e "${NL}${BLUE}Checking if reboot is required...${NC}${NL}"

    # Reboot test for debian / ubuntu based hosts
    if [[ -s /var/run/reboot-required ]]; then
        cat /var/run/reboot-required
    # Reboot test for pop_os
    elif [[ -r /var/run/reboot-required && $(wc -l < /var/run/reboot-required) -eq 0 ]]; then
        echo -e "** Reboot required **${NL}"
    # Reboot test for redhat based hosts
    elif [[ ! $(which needs-restarting 2>/dev/null) == "" ]]; then
        needs-restarting -r
    # Reboot test for archlinux based hosts
    elif [[ $(pacman -Q linux-cachyos 2>/dev/null | cut -d " " -f 2) > $(uname -r | sed -e 's/-cachyos//') ]]; then
        echo -e "** Reboot required **${NL}"
    else
        echo -e "Nothing to do.${NL}"
        exit 0
    fi
}

# OS-Release
source /etc/os-release

# Fix empty 'DISTRO' variable
if [[ -n $ID_LIKE ]]; then
    DISTRO=$ID_LIKE
else
    DISTRO=$ID
fi

# Script header
echo -e "${NL}${BLUE}Basic ${PURPLE}${PRETTY_NAME}${BLUE} semi-automatic update/upgrade script - ${GREEN}v$(get_version)${NC}"

# Show machine hostname
echo -e "${NL}${WHITE}Running on ${GREEN}$(hostname -f)${WHITE}...${NC}"

# Show detected system
echo -e "${NL}${WHITE}Operating System: ${YELLOW}${PRETTY_NAME}${WHITE}${NC}"

# Select proper function
case $DISTRO in
    "debian"|"ubuntu"|"ubuntu debian")
        update_ubuntu
        check_reboot
    ;;
    "redhat"|"rhel fedora"|"rhel centos fedora"|"rancheros")
        update_redhat
        check_reboot
    ;;
    "arch"|"cachyos")
        update_archlinux
        check_reboot
    ;;
    *)
        echo -e "${NL}${RED}OS '${WHITE}${DISTRO}${RED}' not supported.${NC}${NL}"
        exit 1
    ;;
esac
