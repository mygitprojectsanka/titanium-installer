#!/bin/bash
# titanium-installer/lib/common.sh
# Common functions and utilities

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$TITANIUM_ROOT/logs/titanium.log"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$TITANIUM_ROOT/logs/titanium.log"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$TITANIUM_ROOT/logs/titanium.log"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$TITANIUM_ROOT/logs/titanium.log"
}

# Checkpoint functions
check_phase_complete() {
    local phase=$1
    [ -f "$TITANIUM_ROOT/logs/checkpoints/${phase}.complete" ]
}

mark_phase_complete() {
    local phase=$1
    mkdir -p "$TITANIUM_ROOT/logs/checkpoints"
    touch "$TITANIUM_ROOT/logs/checkpoints/${phase}.complete"
    log_success "Phase '$phase' marked as complete"
}

# Disk detection
scan_disks() {
    log_info "Scanning available disks..."
    lsblk -dpno NAME,TYPE,SIZE,MODEL | grep "disk"
}

# ZFS utilities
check_zfs_pools() {
    zpool list 2>/dev/null | tail -n +2 | awk '{print $1}'
}

# Network utilities
get_network_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo
}

# Configuration loader
load_config() {
    local config_file="${1:-$TITANIUM_ROOT/config/defaults.conf}"
    if [ -f "$config_file" ]; then
        source "$config_file"
        log_info "Loaded configuration from: $config_file"
    else
        log_warn "Config file not found: $config_file"
    fi
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Error occurred in script at line: ${BASH_LINENO[0]}"
    return $exit_code
}

trap 'handle_error' ERR
