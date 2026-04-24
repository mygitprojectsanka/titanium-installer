#!/bin/bash
# titanium-installer/lib/ui.sh
# Premium UI components using Whiptail

# Progress gauge with percentage
show_progress() {
    local title=$1
    local text=$2
    local percent=0

    (
        while [ $percent -le 100 ]; do
            echo $percent
            echo "### $text ($percent%)"
            sleep 0.02
            percent=$((percent + 1))
        done
    ) | whiptail --title "$title" --gauge "Starting..." 8 60 0
}

# Multi-select checklist
show_checklist() {
    local title=$1
    local text=$2
    local height=$3
    local width=$4
    local list_height=$5
    shift 5

    whiptail --title "$title" --checklist "$text" $height $width $list_height "$@" 3>&1 1>&2 2>&3
}

# Radio list
show_radiolist() {
    local title=$1
    local text=$2
    local height=$3
    local width=$4
    local list_height=$5
    shift 5

    whiptail --title "$title" --radiolist "$text" $height $width $list_height "$@" 3>&1 1>&2 2>&3
}

# Disk selection dialog
show_disk_selector() {
    local disks=$(scan_disks)
    local options=()

    while IFS= read -r disk; do
        options+=("$disk" "$(lsblk -dno SIZE,MODEL $disk | xargs)" "OFF")
    done <<< "$disks"

    show_checklist "Disk Selection" "Select disks for ZFS pool:" 20 80 10 "${options[@]}"
}

# Confirmation dialog with custom styling
show_confirm() {
    local title=$1
    local message=$2
    whiptail --title "$title" --yes-button "Continue" --no-button "Cancel" --yesno "$message" 12 60
}

# Input with validation
show_input() {
    local title=$1
    local prompt=$2
    local default=$3
    whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3
}

# Password input
show_password() {
    local title=$1
    local prompt=$2
    whiptail --title "$title" --passwordbox "$prompt" 10 60 3>&1 1>&2 2>&3
}

# Message box
show_message() {
    local title=$1
    local message=$2
    local type=${3:-msgbox}

    case $type in
        info)    whiptail --title "$title" --msgbox "$message" 15 70 ;;
        error)   whiptail --title "ERROR: $title" --msgbox "$message" 15 70 ;;
        success) whiptail --title "SUCCESS: $title" --msgbox "$message" 15 70 ;;
    esac
}

# Main category menu
show_category_menu() {
    local choice
    choice=$(whiptail --title "Titanium Installer" \
        --menu "Choose deployment category:" \
        25 78 10 \
        "host" "Host Setup & Optimization" \
        "storage" "Storage & ZFS Configuration" \
        "network" "Network Configuration" \
        "core" "Core Infrastructure" \
        "dns" "DNS & Reverse Proxy" \
        "monitor" "Monitoring Stack" \
        "backup" "Backup Infrastructure" \
        "media" "Media Stack" \
        "docs" "Documents & Notes" \
        "ai" "AI & Development" \
        3>&1 1>&2 2>&3)
    echo $choice
}
