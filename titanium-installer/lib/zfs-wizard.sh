#!/bin/bash
# titanium-installer/lib/zfs-wizard.sh
# Advanced ZFS configuration wizard with disk scanning and pool creation

zfs_main_wizard() {
    local existing_pools
    existing_pools=$(check_zfs_pools)

    if [ -n "$existing_pools" ]; then
        zfs_manage_existing_pools "$existing_pools"
    else
        zfs_create_new_pool
    fi
}

zfs_manage_existing_pools() {
    local pools=$1
    local options=()

    while IFS= read -r pool; do
        local size=$(zpool list -Ho size "$pool")
        local health=$(zpool list -Ho health "$pool")
        options+=("$pool" "Size: $size | Health: $health")
    done <<< "$pools"

    local choice=$(show_radiolist \
        "Existing ZFS Pools" \
        "Select pool to manage:" \
        20 80 8 \
        "${options[@]}")

    if [ -n "$choice" ]; then
        zfs_pool_management_menu "$choice"
    fi
}

zfs_create_new_pool() {
    show_message "ZFS Pool Creation" "No existing ZFS pools found.\n\nStarting disk detection..." "info"

    # Scan disks
    local disks_output=$(scan_disks)
    local options=()
    local disk_count=0

    while IFS=' ' read -r name type size model; do
        if [ "$type" = "disk" ]; then
            # Get by-id path
            local by_id=$(find /dev/disk/by-id/ -lname "*$(basename $name)" | head -1)
            local description="$size - $model"
            if [ -n "$by_id" ]; then
                description="$description [$by_id]"
            fi

            # Detect NVMe vs SATA
            if [[ $name == *"nvme"* ]]; then
                description="NVMe: $description"
            else
                description="SATA: $description"
            fi

            options+=("$name" "$description" "OFF")
            ((disk_count++))
        fi
    done <<< "$disks_output"

    if [ $disk_count -eq 0 ]; then
        show_message "No Disks Found" "No suitable disks detected. Aborting." "error"
        return 1
    fi

    # Disk selection
    local selected_disks=$(show_checklist \
        "Available Disks" \
        "Select disks for new ZFS pool:\n(SPACE to select, ENTER to confirm)" \
        20 90 10 \
        "${options[@]}")

    if [ -z "$selected_disks" ]; then
        show_message "No Selection" "No disks selected. Operation cancelled." "error"
        return 1
    fi

    # Convert selected disks to array
    IFS='"' read -ra disk_array <<< "$selected_disks"

    # Pool configuration
    local pool_name=$(show_input "Pool Name" "Enter ZFS pool name:" "titanium")
    [ -z "$pool_name" ] && return 1

    local raid_level=$(show_radiolist \
        "RAID Configuration" \
        "Select RAID level:" \
        15 60 5 \
        "mirror" "Mirror (RAID1 equivalent)" "ON" \
        "raidz1" "RAIDZ1 (RAID5 equivalent)" "OFF" \
        "raidz2" "RAIDZ2 (RAID6 equivalent)" "OFF" \
        "raidz3" "RAIDZ3 (Triple parity)" "OFF" \
        "stripe" "Stripe (No redundancy)" "OFF")

    local compression=$(show_radiolist \
        "Compression" \
        "Select compression algorithm:" \
        15 60 5 \
        "lz4" "LZ4 - Fast, good compression" "ON" \
        "zstd" "ZSTD - Modern, better compression" "OFF" \
        "zstd-fast" "ZSTD-Fast - Faster variant" "OFF" \
        "gzip-9" "Gzip-9 - Maximum compression" "OFF" \
        "off" "No compression" "OFF")

    local ashift=$(show_radiolist \
        "Sector Size (ashift)" \
        "Select ashift value:" \
        15 60 4 \
        "0" "Auto-detect" "ON" \
        "9" "512B sectors (older HDDs)" "OFF" \
        "12" "4K sectors (modern drives)" "OFF" \
        "13" "8K sectors (some SSDs)" "OFF")

    # Advanced options
    local advanced=$(show_checklist \
        "Advanced Options" \
        "Select additional ZFS features:" \
        15 60 6 \
        "autoexpand" "Enable autoexpand" "ON" \
        "autoreplace" "Enable autoreplace" "ON" \
        "listsnapshots" "Enable snapshot listing" "OFF" \
        "dedup" "Enable deduplication (memory intensive!)" "OFF" \
        "atime_off" "Disable access time (performance)" "ON" \
        "relatime" "Use relative access time" "OFF")

    # Build and execute zpool create command
    build_zpool_command "$pool_name" "$raid_level" "${disk_array[@]}"

    # Create datasets
    create_default_datasets "$pool_name"
}

build_zpool_command() {
    local pool=$1
    local raid=$2
    shift 2
    local disks=("$@")

    # Convert /dev/sdX to by-id paths
    local by_id_disks=()
    for disk in "${disks[@]}"; do
        disk=$(echo "$disk" | tr -d '"')
        local id_path=$(find /dev/disk/by-id/ -lname "*$(basename $disk)*" | grep -v part | head -1)
        if [ -n "$id_path" ]; then
            by_id_disks+=("$id_path")
        else
            by_id_disks+=("$disk")
        fi
    done

    local zpool_cmd="zpool create -f"

    # Build RAID configuration
    case $raid in
        mirror)
            zpool_cmd+=" mirror"
            ;;
        raidz1|raidz2|raidz3)
            zpool_cmd+=" $raid"
            ;;
        stripe)
            # No RAID keyword needed
            ;;
    esac

    zpool_cmd+=" $pool ${by_id_disks[*]}"

    # Add options
    zpool_cmd+=" -o ashift=${ashift:-0}"
    zpool_cmd+=" -o compression=${compression:-lz4}"

    if [[ "$advanced" == *"autoexpand"* ]]; then
        zpool_cmd+=" -o autoexpand=on"
    fi

    if [[ "$advanced" == *"atime_off"* ]]; then
        zpool_cmd+=" -o atime=off"
    elif [[ "$advanced" == *"relatime"* ]]; then
        zpool_cmd+=" -o relatime=on"
    fi

    if [[ "$advanced" == *"dedup"* ]]; then
        show_message "⚠️ Warning" "Deduplication is enabled. Ensure you have sufficient RAM (1GB per TB of storage minimum)." "error"
        zpool_cmd+=" -o dedup=on"
    fi

    # Show summary and confirm
    show_message "Pool Creation Summary" \
        "The following command will be executed:\n\n$zpool_cmd\n\nDisks: ${by_id_disks[*]}\nRAID: $raid\nCompression: ${compression:-lz4}\nashift: ${ashift:-0}" \
        "info"

    if show_confirm "Create Pool" "Proceed with pool creation?"; then
        show_progress "Creating Pool" "Creating ZFS pool '$pool'..."
        if eval "$zpool_cmd"; then
            mark_phase_complete "zfs-pool-creation"
            show_message "Success" "ZFS pool '$pool' created successfully!" "success"
        else
            show_message "Error" "Failed to create pool. Check logs for details." "error"
        fi
    fi
}

create_default_datasets() {
    local pool=$1

    show_progress "Creating Datasets" "Creating default datasets..."

    local datasets=(
        "media"
        "documents"
        "downloads"
        "photos"
        "ai-models"
        "backups"
        "archive"
        "airdrop"
        "appdata"
    )

    for dataset in "${datasets[@]}"; do
        if ! zfs list "$pool/$dataset" &>/dev/null; then
            zfs create -o mountpoint=/mnt/$dataset "$pool/$dataset"
            log_success "Created dataset: $pool/$dataset -> /mnt/$dataset"
        fi
    done

    # Special dataset for databases with recordsize tuning
    if ! zfs list "$pool/databases" &>/dev/null; then
        zfs create -o recordsize=16K -o primarycache=metadata "$pool/databases"
        log_success "Created dataset: $pool/databases (optimized for databases)"
    fi
}

zfs_pool_management_menu() {
    local pool=$1

    while true; do
        local choice=$(whiptail --title "Pool Management: $pool" \
            --menu "Select action:" \
            20 70 10 \
            "1" "Pool Status & Health" \
            "2" "Create Dataset" \
            "3" "Set Pool Properties" \
            "4" "Scrub Pool" \
            "5" "Export/Import Pool" \
            "6" "View I/O Statistics" \
            "7" "Snapshot Management" \
            "8" "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case $choice in
            1) zpool status "$pool" | less ;;
            2) create_custom_dataset "$pool" ;;
            3) set_pool_properties "$pool" ;;
            4) scrub_pool "$pool" ;;
            5) export_import_pool "$pool" ;;
            6) zpool iostat "$pool" 1 ;;
            7) snapshot_management "$pool" ;;
            8) break ;;
        esac
    done
}
