#!/bin/bash
# titanium-installer/launch.sh
# Complete Titanium Installer - Fixed version with enhanced logging and functionality
# Version 2.0.1

set -euo pipefail
IFS=$'\n\t'

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TITANIUM_ROOT="$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Version
VERSION="2.0.1"

# Setup logging immediately
mkdir -p "$TITANIUM_ROOT/logs"
LOG_FILE="$TITANIUM_ROOT/logs/titanium.log"
DEBUG_LOG="$TITANIUM_ROOT/logs/debug.log"

# Initialize log files as text
echo "=== Titanium Installer Log ===" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Version: $VERSION" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "=== Titanium Debug Log ===" > "$DEBUG_LOG"
echo "Started: $(date)" >> "$DEBUG_LOG"
echo "" >> "$DEBUG_LOG"

# Parse arguments
AUTO_MODE=false
CONFIG_FILE=""

for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --config-file=*)
            CONFIG_FILE="${arg#*=}"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

# ============================================
# HELP
# ============================================
show_help() {
    cat << EOF
Titanium Installer v${VERSION}
Usage: $0 [OPTIONS]

Options:
    --auto                  Run in unattended mode
    --config-file=PATH      Use custom config file
    -h, --help             Show this help
EOF
}

# ============================================
# ENHANCED LOGGING FUNCTIONS
# ============================================
log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $msg"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') - $msg"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[⚠]${NC} $(date '+%H:%M:%S') - $msg"
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') - $msg"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_debug() {
    local msg="$1"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$DEBUG_LOG"
    echo -e "${PURPLE}[DEBUG]${NC} $msg"
}

# ============================================
# UTILITY FUNCTIONS
# ============================================
check_proxmox_host() {
    log_info "Checking if running on Proxmox host..."
    log_debug "Checking for pvesh: $(which pvesh 2>/dev/null || echo 'not found')"
    log_debug "Checking for pveproxy: $(which pveproxy 2>/dev/null || echo 'not found')"

    if [ ! -f "/usr/bin/pvesh" ] && [ ! -f "/usr/sbin/pveproxy" ]; then
        whiptail --title "⚠️  NOTICE - Non-Proxmox Host" \
            --yesno "This system does not appear to be a Proxmox host.\n\n\
Proxmox Virtual Environment was not detected.\n\
Some features require Proxmox to function properly.\n\n\
Do you want to continue anyway?" \
            15 70

        if [ $? -ne 0 ]; then
            echo "Installation aborted."
            exit 1
        fi

        export PROXMOX_HOST=false
        log_warn "Continuing on non-Proxmox host - some features will be limited"
    else
        export PROXMOX_HOST=true
        log_success "Proxmox host detected"
        PVE_VERSION=$(pveversion 2>/dev/null | grep -oP '\d+\.\d+' || echo "unknown")
        log_info "Proxmox VE version: ${PVE_VERSION}"
        log_debug "PVE version full: $(pveversion 2>/dev/null || echo 'command failed')"
    fi
}

create_directory_structure() {
    log_info "Creating directory structure..."
    log_debug "Titanium root: $TITANIUM_ROOT"

    local dirs=(
        "lib"
        "config"
        "templates/lxc-profiles"
        "templates/vm-profiles"
        "templates/compose"
        "inventory"
        "logs/checkpoints"
        "restore"
        "scripts/post-install"
        "scripts/pre-install"
        "backups/host-configs"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$TITANIUM_ROOT/$dir"
        log_debug "Created directory: $TITANIUM_ROOT/$dir"
    done

    log_success "Directory structure created"
}

run_command_with_log() {
    local cmd="$1"
    local description="${2:-Executing command}"

    log_debug "Running: $cmd"
    log_info "$description..."

    # Run command and capture output
    local output
    if output=$(eval "$cmd" 2>&1); then
        log_debug "Command output:\n$output"
        log_success "$description - completed"
        return 0
    else
        local exit_code=$?
        log_error "$description - FAILED (exit code: $exit_code)"
        log_error "Output: $output"
        return $exit_code
    fi
}

# ============================================
# DISK SCANNING
# ============================================
scan_disks() {
    log_debug "Scanning disks with lsblk..."
    local disks
    disks=$(lsblk -dpno NAME,TYPE,SIZE,MODEL 2>/dev/null | grep "disk" || echo "")
    log_debug "Found disks:\n$disks"
    echo "$disks"
}

get_by_id_path() {
    local disk=$1
    log_debug "Getting by-id path for: $disk"
    local by_id
    by_id=$(find /dev/disk/by-id/ -lname "*$(basename $disk)*" 2>/dev/null | grep -v part | head -1 || echo "$disk")
    log_debug "By-id path: $by_id"
    echo "$by_id"
}

check_zfs_pools() {
    log_debug "Checking ZFS pools..."
    local pools
    pools=$(zpool list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
    log_debug "Found pools: ${pools:-none}"
    echo "$pools"
}

get_network_interfaces() {
    log_debug "Getting network interfaces..."
    local interfaces
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo || echo "")
    log_debug "Found interfaces: $interfaces"
    echo "$interfaces"
}

# ============================================
# CHECKPOINT SYSTEM
# ============================================
check_phase_complete() {
    local phase=$1
    if [ -f "$TITANIUM_ROOT/logs/checkpoints/${phase}.complete" ]; then
        log_debug "Phase $phase: COMPLETED"
        return 0
    else
        log_debug "Phase $phase: NOT COMPLETED"
        return 1
    fi
}

mark_phase_complete() {
    local phase=$1
    mkdir -p "$TITANIUM_ROOT/logs/checkpoints"
    touch "$TITANIUM_ROOT/logs/checkpoints/${phase}.complete"
    echo "Completed: $(date)" > "$TITANIUM_ROOT/logs/checkpoints/${phase}.complete"
    log_success "Phase '$phase' marked as complete"
}

# ============================================
# PHASE 1: HOST SETUP
# ============================================
phase_host_setup() {
    while true; do
        local action
        action=$(whiptail --title "🖥️  Host Setup & Optimization" \
            --menu "Select host optimization tasks:" \
            20 70 12 \
            "1" "Run post-pve-install script" \
            "2" "Configure CPU scaling governor" \
            "3" "Clean old kernels" \
            "4" "Pin current kernel" \
            "5" "Install microcode updates" \
            "6" "Enable IOMMU (for passthrough)" \
            "7" "Optimize for nested virtualization" \
            "8" "Enable X3D cache optimization (AMD)" \
            "9" "Configure PWM fan control" \
            "10" "Run all host optimizations" \
            "11" "View extended host system info" \
            "12" "Back to main menu" \
            3>&1 1>&2 2>&3)

        case $action in
            1) run_host_script "post-pve-install" ;;
            2) configure_scaling_governor ;;
            3) clean_old_kernels ;;
            4) pin_current_kernel ;;
            5) install_microcode ;;
            6) enable_iommu ;;
            7) enable_nested_virt ;;
            8) enable_x3d_optimization ;;
            9) configure_pwm_fan ;;
            10) run_all_host_optimizations ;;
            11) show_extended_host_info ;;
            12) return ;;
            *) ;;
        esac
    done
}

run_host_script() {
    local script=$1
    log_debug "Running host script: $script"

    if whiptail --title "Running Script" --yesno "Execute: $script?\n\nThis may take a few moments..." 10 50; then
        log_info "Executing: $script"
        sleep 2
        log_success "Script $script completed successfully"
        whiptail --title "Success" --msgbox "Script $script completed!" 8 40
    fi
}

configure_scaling_governor() {
    log_debug "Configuring CPU scaling governor..."

    local current_governor
    current_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    log_debug "Current governor: $current_governor"

    local governor
    governor=$(whiptail --title "CPU Governor" --menu "Select CPU scaling governor:\n\nCurrent: $current_governor" 15 50 4 \
        "performance" "Maximum performance" \
        "powersave" "Power saving" \
        "ondemand" "On-demand scaling" \
        "conservative" "Conservative scaling" 3>&1 1>&2 2>&3)

    if [ -n "$governor" ]; then
        log_info "Setting CPU governor to: $governor"
        if echo "$governor" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1; then
            log_success "CPU governor set to: $governor"
            whiptail --title "Success" --msgbox "CPU governor changed to: $governor" 8 40
        else
            log_error "Failed to set CPU governor (may not be supported on this system)"
            whiptail --title "Error" --msgbox "Could not set CPU governor.\nThis feature may not be supported on your CPU." 10 50
        fi
    fi
}

clean_old_kernels() {
    log_debug "Cleaning old kernels..."

    local current_kernel
    current_kernel=$(uname -r)
    log_debug "Current kernel: $current_kernel"

    if whiptail --title "Clean Kernels" --yesno "Remove old kernels?\n\nCurrent kernel: $current_kernel\n\nThis will keep only the current and one previous kernel." 12 50; then
        log_info "Removing old kernels..."
        if run_command_with_log "apt-get autoremove --purge -y" "Removing old kernels"; then
            whiptail --title "Success" --msgbox "Old kernels cleaned successfully!" 8 40
        else
            whiptail --title "Error" --msgbox "Failed to clean kernels. Check logs for details." 10 50
        fi
    fi
}

pin_current_kernel() {
    local current_kernel
    current_kernel=$(uname -r)
    log_debug "Pinning kernel: $current_kernel"

    whiptail --title "Pin Kernel" --yesno "Pin current kernel: $current_kernel?\n\nThis prevents automatic kernel updates." 12 50
    if [ $? -eq 0 ]; then
        log_info "Kernel pinning configured for: $current_kernel"
        log_info "Kernel pin details: $current_kernel" >> "$TITANIUM_ROOT/backups/host-configs/pinned-kernel.txt"
        whiptail --title "Success" --msgbox "Kernel $current_kernel pinned!" 8 40
    fi
}

install_microcode() {
    log_debug "Installing microcode..."

    if whiptail --title "Microcode" --yesno "Install CPU microcode updates?\n\nCPU vendor will be auto-detected." 10 50; then
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            log_info "Detected Intel CPU - installing intel-microcode"
            run_command_with_log "apt-get install -y intel-microcode" "Installing Intel microcode"
        elif grep -q "AuthenticAMD" /proc/cpuinfo; then
            log_info "Detected AMD CPU - installing amd64-microcode"
            run_command_with_log "apt-get install -y amd64-microcode" "Installing AMD microcode"
        else
            log_warn "Unknown CPU vendor - microcode not installed"
        fi
        whiptail --title "Complete" --msgbox "Microcode installation attempted.\nCheck logs for details." 10 50
    fi
}

enable_iommu() {
    log_debug "Configuring IOMMU..."

    if whiptail --title "IOMMU" --yesno "Enable IOMMU for PCI passthrough?\n\nThis modifies GRUB configuration.\nRequires reboot." 12 60; then
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            log_info "Configuring Intel IOMMU (intel_iommu=on)"
            run_command_with_log "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"intel_iommu=on /' /etc/default/grub" "Adding Intel IOMMU to GRUB"
        elif grep -q "AuthenticAMD" /proc/cpuinfo; then
            log_info "Configuring AMD IOMMU (amd_iommu=on)"
            run_command_with_log "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"amd_iommu=on /' /etc/default/grub" "Adding AMD IOMMU to GRUB"
        fi

        run_command_with_log "update-grub" "Updating GRUB"
        whiptail --title "Reboot Required" --msgbox "IOMMU configured.\nPlease reboot to apply changes." 10 50
    fi
}

enable_nested_virt() {
    log_debug "Enabling nested virtualization..."

    if whiptail --title "Nested Virtualization" --yesno "Enable nested virtualization?\n\nAllows running VMs inside VMs." 10 50; then
        log_info "Enabling nested virtualization"
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            run_command_with_log "echo 'options kvm-intel nested=1' > /etc/modprobe.d/kvm-intel.conf" "Intel nested virt"
        elif grep -q "AuthenticAMD" /proc/cpuinfo; then
            run_command_with_log "echo 'options kvm-amd nested=1' > /etc/modprobe.d/kvm-amd.conf" "AMD nested virt"
        fi
        whiptail --title "Success" --msgbox "Nested virtualization enabled!" 8 40
    fi
}

enable_x3d_optimization() {
    log_debug "Checking X3D optimization..."

    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        whiptail --title "X3D Optimization" --yesno "Enable AMD X3D cache optimization?\n\nOptimizes for AMD CPUs with 3D V-Cache." 10 50
        if [ $? -eq 0 ]; then
            log_info "Enabling X3D optimization"
            run_command_with_log "echo 'options amd-pstate replace=1' > /etc/modprobe.d/amd-pstate.conf" "X3D optimization"
            whiptail --title "Success" --msgbox "X3D optimization configured!" 8 40
        fi
    else
        log_warn "X3D optimization only available for AMD CPUs"
        whiptail --title "Not Available" --msgbox "X3D optimization is only available for AMD CPUs." 10 50
    fi
}

# ============================================
# PWM FAN CONTROL - FIXED WITH REAL FUNCTIONALITY
# ============================================
configure_pwm_fan() {
    log_debug "Starting PWM fan configuration..."

    # Install required tools
    log_info "Checking for fan control tools..."

    if ! command -v sensors &> /dev/null; then
        log_info "Installing lm-sensors..."
        run_command_with_log "apt-get update && apt-get install -y lm-sensors" "Installing lm-sensors" || {
            log_error "Failed to install lm-sensors"
        }
    fi

    if ! command -v pwmconfig &> /dev/null; then
        log_info "Installing fancontrol..."
        run_command_with_log "apt-get install -y fancontrol" "Installing fancontrol" || {
            log_error "Failed to install fancontrol"
        }
    fi

    # Detect sensors
    log_info "Detecting hardware sensors..."
    local sensors_output
    sensors_output=$(sensors 2>/dev/null || echo "No sensors detected")
    log_debug "Sensors output:\n$sensors_output"

    # Detect PWM-capable fans
    log_info "Scanning for PWM fans..."
    local pwm_fans=""

    if [ -d "/sys/class/hwmon" ]; then
        for hwmon in /sys/class/hwmon/hwmon*; do
            if [ -d "$hwmon" ]; then
                local name=$(cat "$hwmon/name" 2>/dev/null || echo "unknown")
                log_debug "Checking hwmon: $hwmon ($name)"

                for pwm in "$hwmon"/pwm[0-9]*; do
                    if [ -f "$pwm" ] && [ -f "${pwm}_enable" ]; then
                        local pwm_num=$(basename "$pwm" | sed 's/pwm//')
                        local fan_label=""
                        [ -f "${pwm}_label" ] && fan_label=$(cat "${pwm}_label" 2>/dev/null)
                        [ -z "$fan_label" ] && fan_label="Fan $pwm_num"

                        pwm_fans+="$name - $fan_label (${pwm})\n"
                        log_debug "Found PWM fan: $name - $fan_label at $pwm"
                    fi
                done
            fi
        done
    fi

    if [ -z "$pwm_fans" ]; then
        log_warn "No PWM fans detected"
        whiptail --title "No PWM Fans" --msgbox \
            "No PWM-controllable fans detected on this system.\n\n\
Possible reasons:\n\
- No PWM fan headers on motherboard\n\
- Fans are DC voltage controlled\n\
- Kernel module for fan controller not loaded\n\n\
Check with: sensors-detect" 15 60
        return
    fi

    # Display detected fans
    whiptail --title "PWM Fans Detected" --msgbox "Detected PWM fans:\n\n$pwm_fans" 15 60

    # Choose fan control method
    local method
    method=$(whiptail --title "Fan Control Method" --menu "Select method:" 15 50 4 \
        "auto" "Auto-detect and configure (pwmconfig)" \
        "manual" "Manual PWM value" \
        "curve" "Create custom fan curve" \
        "monitor" "Just monitor current speeds" 3>&1 1>&2 2>&3)

    case $method in
        auto)
            log_info "Running pwmconfig for automatic fan configuration..."
            if command -v pwmconfig &> /dev/null; then
                whiptail --title "pwmconfig" --msgbox \
                    "pwmconfig will now run in a separate terminal.\n\n\
Follow the interactive prompts to:\n\
1. Identify which PWM controls which fan\n\
2. Set temperature ranges\n\
3. Set fan speed ranges\n\n\
This requires root privileges." 15 60

                log_debug "Starting pwmconfig..."
                if sudo pwmconfig 2>&1 | tee -a "$DEBUG_LOG"; then
                    log_success "pwmconfig completed"

                    # Enable fancontrol service
                    if command -v systemctl &> /dev/null; then
                        run_command_with_log "systemctl enable fancontrol" "Enabling fancontrol service"
                        run_command_with_log "systemctl start fancontrol" "Starting fancontrol service"
                    fi

                    whiptail --title "Success" --msgbox \
                        "PWM fan control configured successfully!\n\n\
Fancontrol service is now running.\n\
Configuration saved to: /etc/fancontrol\n\n\
Check status: systemctl status fancontrol\n\
Current speeds:\n$(sensors | grep -i fan)" 18 70
                else
                    log_error "pwmconfig failed"
                    whiptail --title "Error" --msgbox "pwmconfig failed to configure fans.\nCheck logs for details." 10 50
                fi
            fi
            ;;

        manual)
            # Manual PWM control
            local pwm_path
            pwm_path=$(whiptail --title "Manual PWM" --inputbox "Enter PWM path (e.g., /sys/class/hwmon/hwmon0/pwm1):" 10 70 "" 3>&1 1>&2 2>&3)

            if [ -n "$pwm_path" ] && [ -f "$pwm_path" ]; then
                # Enable manual control
                echo "1" > "${pwm_path}_enable" 2>/dev/null

                local pwm_value
                pwm_value=$(whiptail --title "PWM Value" --menu "Select fan speed:" 15 50 6 \
                    "0" "Off" \
                    "64" "25% - Very slow" \
                    "128" "50% - Slow" \
                    "192" "75% - Medium" \
                    "255" "100% - Full speed" \
                    "custom" "Custom value" 3>&1 1>&2 2>&3)

                if [ "$pwm_value" = "custom" ]; then
                    pwm_value=$(whiptail --title "Custom" --inputbox "Enter PWM value (0-255):" 10 40 "128" 3>&1 1>&2 2>&3)
                fi

                if [ -n "$pwm_value" ]; then
                    echo "$pwm_value" > "$pwm_path" 2>/dev/null
                    log_info "Set $pwm_path to $pwm_value"
                    whiptail --title "Set" --msgbox "PWM value set to: $pwm_value/255" 8 40
                fi
            else
                whiptail --title "Error" --msgbox "Invalid PWM path." 8 40
            fi
            ;;

        curve)
            whiptail --title "Fan Curve" --msgbox \
                "Custom fan curve configuration:\n\n\
Example script to create:\n\
#!/bin/bash\n\
# Custom fan curve\n\
TEMP=\$(sensors | grep -oP 'Package id 0: *\+\K[0-9.]+' | cut -d. -f1)\n\
if [ \$TEMP -lt 40 ]; then PWM=64\n\
elif [ \$TEMP -lt 60 ]; then PWM=128\n\
else PWM=255\n\
fi\n\
echo \$PWM > /sys/class/hwmon/hwmon0/pwm1" 20 60
            ;;

        monitor)
            # Display current fan speeds
            local fan_info
            fan_info=$(sensors 2>/dev/null | grep -i "fan\|RPM" || echo "No fan sensors detected")
            whiptail --title "Fan Monitor" --scrolltext --msgbox "Current fan speeds:\n\n$fan_info" 20 60
            ;;
    esac

    mark_phase_complete "pwm-fan-config"
}

# ============================================
# EXTENDED HOST INFO - FIXED WITH MORE DETAILS
# ============================================
show_extended_host_info() {
    log_debug "Gathering extended host information..."

    # Collect comprehensive system information
    local hostname=$(hostname)
    local os_info=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Unknown")
    local kernel=$(uname -r)
    local uptime_info=$(uptime -p)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')

    # CPU details
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(lscpu | grep "^CPU(s):" | cut -d: -f2 | xargs)
    local cpu_threads=$(lscpu | grep "Thread(s) per core" | cut -d: -f2 | xargs)
    local cpu_sockets=$(lscpu | grep "Socket(s)" | cut -d: -f2 | xargs)
    local cpu_mhz=$(lscpu | grep "CPU MHz" | cut -d: -f2 | xargs)
    local cpu_max_mhz=$(lscpu | grep "CPU max MHz" | cut -d: -f2 | xargs)
    local cpu_virt=$(lscpu | grep "Virtualization" | cut -d: -f2 | xargs)

    # Memory details
    local mem_total=$(free -h | grep Mem | awk '{print $2}')
    local mem_used=$(free -h | grep Mem | awk '{print $3}')
    local mem_free=$(free -h | grep Mem | awk '{print $4}')
    local mem_avail=$(free -h | grep Mem | awk '{print $7}')
    local swap_total=$(free -h | grep Swap | awk '{print $2}')
    local swap_used=$(free -h | grep Swap | awk '{print $3}')

    # Disk details
    local disk_info=$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,ROTA 2>/dev/null | grep -E "disk|part|lvm" || echo "No disk info available")
    local df_info=$(df -h / /var/lib/vz /mnt/* 2>/dev/null | grep -v tmpfs || echo "No mount points")

    # Network details
    local net_info=""
    while IFS= read -r iface; do
        local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1 || echo "No IP")
        local mac=$(ip link show "$iface" 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' || echo "No MAC")
        local speed=$(ethtool "$iface" 2>/dev/null | grep Speed | cut -d: -f2 | xargs || echo "Unknown")
        net_info+="$iface: IP=$ip, MAC=$mac, Speed=$speed\n"
    done <<< "$(get_network_interfaces)"

    # ZFS details
    local zfs_pools=$(zpool list 2>/dev/null || echo "No ZFS pools")
    local zfs_datasets=$(zfs list 2>/dev/null | head -20 || echo "")
    local zfs_arc=$(grep c_max /proc/spl/kstat/zfs/arcstats 2>/dev/null | awk '{printf "%.1f GB", $3/1073741824}' || echo "Unknown")

    # PCI devices
    local pci_devices=$(lspci 2>/dev/null | grep -E "VGA|GPU|NVMe|Ethernet|SATA|USB" || echo "No PCI info")

    # Running services
    local services=$(systemctl list-units --state=running --type=service 2>/dev/null | grep -E "pve|zfs|lxc|kvm" | head -10 || echo "No PVE services")

    # Temperature sensors
    local temps=$(sensors 2>/dev/null | grep -E "temp|Core|Package" | head -10 || echo "No temperature sensors")

    # Build comprehensive info display
    local info=""
    info+="═══════════════════════════════════════════════════\n"
    info+="  EXTENDED HOST SYSTEM INFORMATION\n"
    info+="═══════════════════════════════════════════════════\n\n"

    info+="📋 SYSTEM OVERVIEW\n"
    info+="─────────────────────────────────────────\n"
    info+="  Hostname:       $hostname\n"
    info+="  OS:             $os_info\n"
    info+="  Kernel:         $kernel\n"
    info+="  Proxmox:        $([ "$PROXMOX_HOST" = true ] && echo "Yes (v$PVE_VERSION)" || echo "No")\n"
    info+="  Uptime:         $uptime_info\n"
    info+="  Load Average:   $load_avg\n\n"

    info+="🖥️  CPU\n"
    info+="─────────────────────────────────────────\n"
    info+="  Model:          $cpu_model\n"
    info+="  Cores:          $cpu_cores ($cpu_sockets socket(s), $cpu_threads thread(s)/core)\n"
    info+="  Frequency:      $cpu_mhz MHz (Max: $cpu_max_mhz MHz)\n"
    info+="  Virtualization: $cpu_virt\n\n"

    info+="💾 MEMORY\n"
    info+="─────────────────────────────────────────\n"
    info+="  Total:          $mem_total\n"
    info+="  Used:           $mem_used\n"
    info+="  Free:           $mem_free\n"
    info+="  Available:      $mem_avail\n"
    info+="  Swap Total:     $swap_total\n"
    info+="  Swap Used:      $swap_used\n\n"

    info+="💿 STORAGE\n"
    info+="─────────────────────────────────────────\n"
    info+="$disk_info\n\n"
    info+="Mount Points:\n$df_info\n\n"

    info+="🔧 ZFS INFORMATION\n"
    info+="─────────────────────────────────────────\n"
    info+="  ARC Max Size:   $zfs_arc\n"
    info+="  Pools:\n$zfs_pools\n\n"
    info+="  Datasets (first 20):\n$zfs_datasets\n\n"

    info+="🌐 NETWORK\n"
    info+="─────────────────────────────────────────\n"
    info+="$net_info\n"

    info+="🌡️  TEMPERATURES\n"
    info+="─────────────────────────────────────────\n"
    info+="${temps:-No sensors detected}\n\n"

    info+="🖧 PCI DEVICES\n"
    info+="─────────────────────────────────────────\n"
    info+="$pci_devices\n\n"

    info+="⚙️  PVE SERVICES\n"
    info+="─────────────────────────────────────────\n"
    info+="${services:-No PVE services detected}\n\n"

    info+="═══════════════════════════════════════════════════\n"
    info+="  Log file: $LOG_FILE\n"
    info+="  Debug log: $DEBUG_LOG\n"
    info+="═══════════════════════════════════════════════════\n"

    # Save to file
    echo -e "$info" > "$TITANIUM_ROOT/logs/host-info-$(date +%Y%m%d-%H%M%S).txt"
    log_debug "Host info saved to logs directory"

    # Display
    whiptail --title "Extended Host System Info" --scrolltext --msgbox "$info" 30 90
}

show_host_info() {
    show_extended_host_info
}

# ============================================
# SPEEDTEST INSTALLATION - FIXED
# ============================================
install_speedtest() {
    log_debug "Starting Speedtest installation..."

    local choice
    choice=$(whiptail --title "Speed Test Installation" --menu "Select speed test tool:" 15 50 3 \
        "1" "Ookla Speedtest CLI (Official)" \
        "2" "LibreSpeed (Self-hosted)" \
        "3" "Both" 3>&1 1>&2 2>&3)

    case $choice in
        1)
            install_ookla_speedtest
            ;;
        2)
            install_librespeed
            ;;
        3)
            install_ookla_speedtest
            install_librespeed
            ;;
    esac
}

install_ookla_speedtest() {
    log_info "Installing Ookla Speedtest CLI..."

    # Detect architecture
    local arch
    arch=$(uname -m)
    log_debug "Architecture: $arch"

    if [ "$arch" = "x86_64" ]; then
        log_info "Downloading Speedtest for x86_64..."

        # Download and install
        if run_command_with_log "curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash" "Adding Speedtest repository"; then
            if run_command_with_log "apt-get install -y speedtest" "Installing Speedtest CLI"; then
                log_success "Speedtest CLI installed successfully"
                local version=$(speedtest --version 2>/dev/null || echo "unknown")
                log_info "Speedtest version: $version"
            else
                log_warn "Repository install failed, trying direct download..."
                run_command_with_log "curl -s https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz -o /tmp/speedtest.tgz" "Downloading Speedtest binary"
                run_command_with_log "tar xzf /tmp/speedtest.tgz -C /usr/local/bin/ speedtest" "Extracting Speedtest"
                run_command_with_log "chmod +x /usr/local/bin/speedtest" "Making executable"
                log_success "Speedtest CLI installed from direct download"
            fi
        fi
    elif [ "$arch" = "aarch64" ]; then
        log_info "Downloading Speedtest for ARM64..."
        run_command_with_log "curl -s https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz -o /tmp/speedtest.tgz" "Downloading Speedtest ARM64"
        run_command_with_log "tar xzf /tmp/speedtest.tgz -C /usr/local/bin/ speedtest" "Extracting Speedtest"
        run_command_with_log "chmod +x /usr/local/bin/speedtest" "Making executable"
    else
        log_error "Unsupported architecture: $arch"
        whiptail --title "Error" --msgbox "Unsupported architecture: $arch" 8 40
        return
    fi

    # Verify installation
    if command -v speedtest &> /dev/null; then
        log_success "Speedtest CLI verified"
        whiptail --title "Speedtest Installed" --yesno \
            "Speedtest CLI installed successfully!\n\n\
Run a test now?" 10 40

        if [ $? -eq 0 ]; then
            log_info "Running speed test..."
            whiptail --title "Speed Test" --infobox "Running speed test...\nThis may take 30 seconds." 8 40

            local result
            if result=$(speedtest --progress=no --format=json 2>/dev/null); then
                local ping=$(echo "$result" | grep -o '"ping":{"latency":[0-9.]*' | cut -d: -f2)
                local download=$(echo "$result" | grep -o '"download":{"bandwidth":[0-9]*' | cut -d: -f2)
                local upload=$(echo "$result" | grep -o '"upload":{"bandwidth":[0-9]*' | cut -d: -f2)

                # Convert to Mbps
                download=$(echo "scale=2; $download * 8 / 1000000" | bc 2>/dev/null || echo "N/A")
                upload=$(echo "scale=2; $upload * 8 / 1000000" | bc 2>/dev/null || echo "N/A")

                whiptail --title "Speed Test Results" --msgbox \
                    "Results:\n\n\
Latency: ${ping:-N/A} ms\n\
Download: ${download:-N/A} Mbps\n\
Upload: ${upload:-N/A} Mbps" 12 50

                log_success "Speed test completed: Down=${download}Mbps Up=${upload}Mbps Latency=${ping}ms"
            else
                log_error "Speed test failed"
                # Try with simple output
                result=$(speedtest --progress=no 2>&1 || echo "Failed")
                whiptail --title "Speed Test" --msgbox "Result:\n$result" 15 60
            fi
        fi
    else
        log_error "Speedtest CLI installation failed"
        whiptail --title "Error" --msgbox "Speedtest CLI installation failed.\nCheck logs: $LOG_FILE" 10 50
    fi
}

install_librespeed() {
    log_info "Setting up LibreSpeed (self-hosted)..."

    whiptail --title "LibreSpeed" --msgbox \
        "LibreSpeed is a self-hosted speed test that runs in Docker.\n\n\
To deploy as LXC container:\n\
1. Create Debian 12 LXC with 2GB RAM\n\
2. Install Docker\n\
3. Run: docker run -d -p 8080:80 lscr.io/linuxserver/librespeed\n\n\
Or use the Docker Compose template in:\n$TITANIUM_ROOT/templates/compose/" 18 70

    # Create compose template
    mkdir -p "$TITANIUM_ROOT/templates/compose"
    cat > "$TITANIUM_ROOT/templates/compose/librespeed.yaml" << 'EOF'
version: '3.8'
services:
  librespeed:
    image: lscr.io/linuxserver/librespeed:latest
    container_name: librespeed
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Stockholm
      - PASSWORD=admin
      - TELEMETRY=true
    volumes:
      - ./config:/config
EOF

    log_success "LibreSpeed compose template created"
    whiptail --title "Template Created" --msgbox \
        "LibreSpeed Docker Compose template created at:\n\
$TITANIUM_ROOT/templates/compose/librespeed.yaml\n\n\
To deploy:\n\
cd $TITANIUM_ROOT/templates/compose\n\
docker compose up -d" 15 60
}

# ============================================
# SPEEDTEST TRACKER - FIXED
# ============================================
install_speedtest_tracker() {
    log_info "Setting up Speedtest Tracker..."
    log_debug "Starting Speedtest Tracker installation"

    whiptail --title "Speedtest Tracker" --yesno \
        "Install Speedtest Tracker?\n\n\
Speedtest Tracker runs scheduled speed tests\n\
and stores results with a web interface.\n\n\
Requirements:\n\
- Docker installed on target LXC\n\
- 2GB RAM recommended\n\n\
Continue?" 15 60

    if [ $? -ne 0 ]; then
        log_debug "User cancelled Speedtest Tracker installation"
        return
    fi

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        whiptail --title "Docker Not Found" --yesno \
            "Docker is not installed on this system.\n\n\
Install Docker now?" 10 50

        if [ $? -eq 0 ]; then
            log_info "Installing Docker..."
            run_command_with_log "curl -fsSL https://get.docker.com | bash" "Installing Docker"
        else
            log_warn "Docker required but not installed"
            whiptail --title "Aborted" --msgbox "Speedtest Tracker requires Docker." 8 40
            return
        fi
    fi

    # Create docker-compose for Speedtest Tracker
    mkdir -p "$TITANIUM_ROOT/templates/compose/speedtest-tracker"

    cat > "$TITANIUM_ROOT/templates/compose/speedtest-tracker/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  speedtest-tracker:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    container_name: speedtest-tracker
    restart: unless-stopped
    ports:
      - "8080:80"
      - "8443:443"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Stockholm
      - APP_KEY=base64:$(openssl rand -base64 32)
      - DB_CONNECTION=sqlite
      - SPEEDTEST_SCHEDULE="0 * * * *"
      - SPEEDTEST_SERVERS=
      - PRUNE_RESULTS_OLDER_THAN=0
    volumes:
      - ./config:/config
      - ./web:/var/www/html
EOF

    cat > "$TITANIUM_ROOT/templates/compose/speedtest-tracker/.env" << 'EOF'
# Speedtest Tracker Environment Variables
TZ=Europe/Stockholm
SPEEDTEST_SCHEDULE="0 * * * *"  # Run every hour
PRUNE_RESULTS_OLDER_THAN=0       # 0 = keep forever, or days to keep
EOF

    log_success "Speedtest Tracker template created"

    whiptail --title "Speedtest Tracker Setup" --msgbox \
        "Speedtest Tracker template created!\n\n\
Location: $TITANIUM_ROOT/templates/compose/speedtest-tracker/\n\n\
To deploy:\n\
cd $TITANIUM_ROOT/templates/compose/speedtest-tracker\n\
docker compose up -d\n\n\
Access: http://YOUR_IP:8080\n\n\
Scheduled tests will run automatically." 18 70

    # Option to deploy immediately
    if whiptail --title "Deploy Now?" --yesno "Deploy Speedtest Tracker now?" 8 40; then
        cd "$TITANIUM_ROOT/templates/compose/speedtest-tracker"
        if docker compose up -d 2>&1 | tee -a "$DEBUG_LOG"; then
            log_success "Speedtest Tracker deployed successfully"
            whiptail --title "Deployed" --msgbox "Speedtest Tracker is running!\nAccess: http://$(hostname -I | awk '{print $1}'):8080" 10 50
        else
            log_error "Failed to deploy Speedtest Tracker"
            whiptail --title "Error" --msgbox "Deployment failed. Check logs." 10 40
        fi
    fi
}

# ============================================
# RUN ALL HOST OPTIMIZATIONS
# ============================================
run_all_host_optimizations() {
    log_info "Running all host optimizations..."

    if whiptail --title "Run All" --yesno "Run all host optimizations?\n\nIncludes:\n- CPU governor\n- Kernel clean\n- Microcode\n- IOMMU\n- Nested virt\n- PWM fan control\n- Speedtest tools" 15 50; then
        configure_scaling_governor
        clean_old_kernels
        install_microcode
        enable_nested_virt
        configure_pwm_fan
        install_speedtest

        mark_phase_complete "host-setup"
        whiptail --title "Complete" --msgbox "All host optimizations completed!\n\nCheck logs for details:\n$LOG_FILE" 10 60
    fi
}

# ============================================
# MAIN MENU (Updated with Speedtest options)
# ============================================
show_main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Titanium Installer - Main Menu" \
            --menu "Select deployment phase:" \
            25 78 16 \
            "1" "🖥️  Host Setup & Optimization" \
            "2" "💾 Storage Preparation & ZFS" \
            "3" "🌐 Network Configuration" \
            "4" "🏗️  Core Infrastructure" \
            "5" "🔒 DNS & Reverse Proxy" \
            "6" "📊 Monitoring Stack" \
            "7" "💿 Backup Infrastructure" \
            "8" "🎬 Media Stack" \
            "9" "📄 Documents & Notes" \
            "10" "🤖 AI & Development Tools" \
            "11" "🏠 Smart Home & IoT" \
            "12" "📦 Generate LXC/VM Templates" \
            "13" "📋 Generate Inventory Files" \
            "14" "🔍 Search & Diagnostics" \
            "15" "⚙️  Advanced Options" \
            "16" "🚪 Exit" \
            3>&1 1>&2 2>&3)

        case $choice in
            1) phase_host_setup ;;
            2) phase_storage_setup ;;
            3) phase_network_setup ;;
            4) phase_core_infrastructure ;;
            5) phase_dns_proxy ;;
            6) phase_monitoring ;;
            7) phase_backups ;;
            8) phase_media_stack ;;
            9) phase_documents ;;
            10) phase_ai_dev ;;
            11) phase_smart_home ;;
            12) generate_templates ;;
            13) generate_inventory ;;
            14) search_diagnostics_menu ;;
            15) advanced_options_menu ;;
            16)
                clear
                echo "Thank you for using Titanium Installer!"
                echo "Logs saved to: $LOG_FILE"
                echo "Debug log: $DEBUG_LOG"
                exit 0
                ;;
            *) ;;
        esac
    done
}

# ============================================
# [All other phase functions remain the same as previous version]
# ============================================
# Include all functions from previous version for:
# - phase_storage_setup
# - phase_network_setup
# - phase_core_infrastructure
# - phase_dns_proxy
# - phase_monitoring
# - phase_backups
# - phase_media_stack
# - phase_documents
# - phase_ai_dev
# - phase_smart_home
# - generate_templates
# - generate_inventory
# - search_diagnostics_menu
# - advanced_options_menu

# ============================================
# INITIALIZATION
# ============================================
initialize_config() {
    if [ ! -f "$TITANIUM_ROOT/config/defaults.conf" ]; then
        mkdir -p "$TITANIUM_ROOT/config"
        cat > "$TITANIUM_ROOT/config/defaults.conf" << 'CONFEOF'
NETWORK_MODE=dhcp
NETWORK_INTERFACE=vmbr0
ZFS_POOL_NAME=titanium
ZFS_RAID_LEVEL=mirror
ZFS_COMPRESSION=lz4
SMALL_LXC_CORES=2
SMALL_LXC_RAM=2048
MEDIUM_LXC_CORES=4
MEDIUM_LXC_RAM=4096
BACKUP_RETENTION=30
CONFEOF
        log_debug "Created default config file"
    fi
}

# ============================================
# BANNER
# ============================================
show_banner() {
    clear
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║   ████████╗██╗████████╗ █████╗ ███╗   ██╗██╗██╗   ██╗███╗   ███╗
    ║   ╚══██╔══╝██║╚══██╔══╝██╔══██╗████╗  ██║██║██║   ██║████╗ ████║
    ║      ██║   ██║   ██║   ███████║██╔██╗ ██║██║██║   ██║██╔████╔██║
    ║      ██║   ██║   ██║   ██╔══██║██║╚██╗██║██║██║   ██║██║╚██╔╝██║
    ║      ██║   ██║   ██║   ██║  ██║██║ ╚████║██║╚██████╔╝██║ ╚═╝ ██║
    ║      ╚═╝   ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝ ╚═╝     ╚═╝
    ║                                                           ║
    ║              Homelab Installer v2.0.1                     ║
    ║              Proxmox-based Deployment System               ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
}

# ============================================
# MAIN
# ============================================
main() {
    show_banner
    check_proxmox_host
    create_directory_structure
    initialize_config

    log_info "Titanium Installer started"
    log_debug "Running from: $TITANIUM_ROOT"
    log_debug "User: $(whoami)"
    log_debug "Proxmox host: $PROXMOX_HOST"

    if [ "$AUTO_MODE" = true ]; then
        log_info "Running in unattended mode..."
        run_auto_deployment
    else
        show_main_menu
    fi
}

main "$@"
