#!/bin/bash
# titanium-installer/lib/checkpoint.sh
# Phase checkpointing system for resumable deployments

# Checkpoint storage
CHECKPOINT_DIR="$TITANIUM_ROOT/logs/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

# Define deployment phases and dependencies
declare -A PHASE_DEPENDENCIES
PHASE_DEPENDENCIES=(
    ["host-setup"]=""
    ["storage-setup"]="host-setup"
    ["network-setup"]="host-setup"
    ["core-infra"]="storage-setup network-setup"
    ["dns-proxy"]="core-infra"
    ["monitoring"]="dns-proxy"
    ["backups"]="storage-setup"
    ["media-stack"]="dns-proxy backups"
    ["documents"]="dns-proxy"
    ["ai-dev"]="dns-proxy"
    ["smart-home"]="dns-proxy"
)

check_dependencies() {
    local phase=$1
    local deps=${PHASE_DEPENDENCIES[$phase]}

    if [ -z "$deps" ]; then
        return 0
    fi

    for dep in $deps; do
        if ! check_phase_complete "$dep"; then
            show_message "Dependency Missing" \
                "Phase '$phase' requires '$dep' to be completed first.\nPlease complete '$dep' before proceeding." \
                "error"
            return 1
        fi
    done
    return 0
}

get_phase_status() {
    local phase=$1
    if check_phase_complete "$phase"; then
        echo "✓ Completed"
    else
        echo "○ Pending"
    fi
}

show_deployment_status() {
    local text="Current Deployment Status:\n\n"

    for phase in "${!PHASE_DEPENDENCIES[@]}"; do
        local status=$(get_phase_status "$phase")
        text+="$(printf '%-20s %s\n' "$phase:" "$status")\n"
    done

    show_message "Deployment Status" "$text" "info"
}

resume_deployment() {
    if [ -f "$CHECKPOINT_DIR/last-phase" ]; then
        local last_phase=$(cat "$CHECKPOINT_DIR/last-phase")
        if show_confirm "Resume" "Resume from last incomplete phase: $last_phase?"; then
            execute_phase "$last_phase"
            return
        fi
    fi

    show_message "No Resume Point" "No incomplete phase found to resume." "info"
}

execute_phase() {
    local phase=$1

    if ! check_dependencies "$phase"; then
        return
    fi

    echo "$phase" > "$CHECKPOINT_DIR/last-phase"

    case $phase in
        host-setup) phase_host_setup ;;
        storage-setup) phase_storage_setup ;;
        network-setup) phase_network_setup ;;
        core-infra) phase_core_infrastructure ;;
        dns-proxy) phase_dns_proxy ;;
        monitoring) phase_monitoring ;;
        backups) phase_backups ;;
        media-stack) phase_media_stack ;;
        documents) phase_documents ;;
        ai-dev) phase_ai_dev ;;
        smart-home) phase_smart_home ;;
    esac

    if [ $? -eq 0 ]; then
        mark_phase_complete "$phase"
        rm -f "$CHECKPOINT_DIR/last-phase"
    fi
}
