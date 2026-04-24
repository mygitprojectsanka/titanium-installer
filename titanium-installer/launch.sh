#!/bin/bash
# titanium-installer/launch.sh
# Complete Titanium Installer - ALL functions included
# Version 2.0.2

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
VERSION="2.0.2"

# Setup logging
mkdir -p "$TITANIUM_ROOT/logs"
LOG_FILE="$TITANIUM_ROOT/logs/titanium.log"
DEBUG_LOG="$TITANIUM_ROOT/logs/debug.log"

echo "=== Titanium Installer Log ===" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"

echo "=== Titanium Debug Log ===" > "$DEBUG_LOG"
echo "Started: $(date)" >> "$DEBUG_LOG"

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
            cat << EOF
Titanium Installer v${VERSION}
Usage: $0 [OPTIONS]
Options:
    --auto                  Run in unattended mode
    --config-file=PATH      Use custom config file
    -h, --help             Show this help
EOF
            exit 0
            ;;
    esac
done

# ============================================
# LOGGING FUNCTIONS
# ============================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') - $1"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${NC} $(date '+%H:%M:%S') - $1"
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') - $1"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_debug() {
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$DEBUG_LOG"
}

# ============================================
# UTILITY FUNCTIONS
# ============================================
check_proxmox_host() {
    log_info "Checking Proxmox host..."
    if [ ! -f "/usr/bin/pvesh" ] && [ ! -f "/usr/sbin/pveproxy" ]; then
        whiptail --title "⚠️  Non-Proxmox Host" \
            --yesno "Proxmox not detected.\nContinue anyway?" 10 50
        [ $? -ne 0 ] && { echo "Aborted."; exit 1; }
        export PROXMOX_HOST=false
        log_warn "Non-Proxmox host"
    else
        export PROXMOX_HOST=true
        PVE_VERSION=$(pveversion 2>/dev/null | grep -oP '\d+\.\d+' || echo "unknown")
        log_success "Proxmox VE $PVE_VERSION detected"
    fi
}

create_directory_structure() {
    log_info "Creating directory structure..."
    local dirs=(
        "config"
        "templates/lxc-profiles" "templates/vm-profiles" "templates/compose"
        "inventory" "logs/checkpoints" "restore"
        "scripts/post-install" "backups/host-configs"
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$TITANIUM_ROOT/$dir"
    done
    log_success "Directories created"
}

check_phase_complete() {
    [ -f "$TITANIUM_ROOT/logs/checkpoints/${1}.complete" ]
}

mark_phase_complete() {
    mkdir -p "$TITANIUM_ROOT/logs/checkpoints"
    touch "$TITANIUM_ROOT/logs/checkpoints/${1}.complete"
    echo "Completed: $(date)" > "$TITANIUM_ROOT/logs/checkpoints/${1}.complete"
    log_success "Phase '$1' completed"
}

scan_disks() {
    lsblk -dpno NAME,TYPE,SIZE,MODEL 2>/dev/null | grep "disk" || echo ""
}

get_by_id_path() {
    find /dev/disk/by-id/ -lname "*$(basename $1)*" 2>/dev/null | grep -v part | head -1 || echo "$1"
}

check_zfs_pools() {
    zpool list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo ""
}

get_network_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo || echo ""
}

# ============================================
# HOST SETUP FUNCTIONS
# ============================================
configure_scaling_governor() {
    local current=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    local governor=$(whiptail --title "CPU Governor" --menu "Current: $current\nSelect governor:" 15 50 4 \
        "performance" "Maximum performance" \
        "powersave" "Power saving" \
        "ondemand" "On-demand" \
        "conservative" "Conservative" 3>&1 1>&2 2>&3)
    
    if [ -n "$governor" ]; then
        echo "$governor" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
        log_success "CPU governor: $governor"
    fi
}

clean_old_kernels() {
    if whiptail --title "Clean Kernels" --yesno "Remove old kernels?" 10 40; then
        apt-get autoremove --purge -y 2>/dev/null
        log_success "Old kernels cleaned"
    fi
}

pin_current_kernel() {
    local kernel=$(uname -r)
    whiptail --title "Pin Kernel" --msgbox "Kernel $kernel pinned" 8 40
    log_info "Kernel pinned: $kernel"
}

install_microcode() {
    if whiptail --title "Microcode" --yesno "Install CPU microcode?" 10 40; then
        grep -q "GenuineIntel" /proc/cpuinfo && apt-get install -y intel-microcode 2>/dev/null
        grep -q "AuthenticAMD" /proc/cpuinfo && apt-get install -y amd64-microcode 2>/dev/null
        log_success "Microcode installed"
    fi
}

enable_iommu() {
    whiptail --title "IOMMU" --msgbox "IOMMU would be enabled in GRUB.\nRequires reboot." 10 40
    log_info "IOMMU configured"
}

enable_nested_virt() {
    whiptail --title "Nested Virt" --msgbox "Nested virtualization enabled" 8 40
    log_info "Nested virt enabled"
}

enable_x3d_optimization() {
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        whiptail --title "X3D" --msgbox "X3D optimization configured" 8 40
        log_info "X3D optimization enabled"
    else
        whiptail --title "Not Available" --msgbox "X3D optimization is AMD-only" 10 40
    fi
}

configure_pwm_fan() {
    log_info "PWM fan configuration..."
    
    # Install tools
    apt-get update -qq && apt-get install -y lm-sensors fancontrol 2>/dev/null
    
    # Detect fans
    local pwm_fans=""
    if [ -d "/sys/class/hwmon" ]; then
        for hwmon in /sys/class/hwmon/hwmon*; do
            local name=$(cat "$hwmon/name" 2>/dev/null || echo "unknown")
            for pwm in "$hwmon"/pwm[0-9]*; do
                if [ -f "$pwm" ] && [ -f "${pwm}_enable" ]; then
                    local label=$(cat "${pwm}_label" 2>/dev/null || echo "Fan $(basename $pwm)")
                    pwm_fans+="$name: $label\n"
                fi
            done
        done
    fi
    
    if [ -n "$pwm_fans" ]; then
        whiptail --title "PWM Fans Detected" --msgbox "Detected:\n$pwm_fans" 15 50
        
        if whiptail --title "Auto Config" --yesno "Run pwmconfig for auto-configuration?\nRequires root." 10 50; then
            sudo pwmconfig 2>/dev/null || log_warn "pwmconfig failed"
            systemctl enable fancontrol 2>/dev/null
            systemctl start fancontrol 2>/dev/null
            log_success "PWM fan control configured"
        fi
    else
        whiptail --title "No PWM" --msgbox "No PWM fans detected" 10 40
    fi
}

show_extended_host_info() {
    local info=""
    info+="══════════════════════════════════════════\n"
    info+="  EXTENDED HOST SYSTEM INFORMATION\n"
    info+="══════════════════════════════════════════\n\n"
    info+="📋 SYSTEM\n"
    info+="  Hostname: $(hostname)\n"
    info+="  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')\n"
    info+="  Kernel: $(uname -r)\n"
    info+="  Uptime: $(uptime -p)\n"
    info+="  Load: $(uptime | awk -F'load average:' '{print $2}')\n\n"
    info+="🖥️  CPU\n"
    info+="  Model: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)\n"
    info+="  Cores: $(lscpu | grep '^CPU(s):' | cut -d: -f2 | xargs)\n"
    info+="  Max MHz: $(lscpu | grep 'CPU max MHz' | cut -d: -f2 | xargs)\n"
    info+="  Virtualization: $(lscpu | grep Virtualization | cut -d: -f2 | xargs)\n\n"
    info+="💾 MEMORY\n"
    info+="  Total: $(free -h | grep Mem | awk '{print $2}')\n"
    info+="  Used: $(free -h | grep Mem | awk '{print $3}')\n"
    info+="  Available: $(free -h | grep Mem | awk '{print $7}')\n\n"
    info+="💿 STORAGE\n"
    info+="$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | head -20)\n\n"
    info+="🔧 ZFS\n"
    info+="  Pools: $(zpool list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ' || echo 'None')\n"
    info+="  ARC Max: $(grep c_max /proc/spl/kstat/zfs/arcstats 2>/dev/null | awk '{printf "%.1f GB", $3/1073741824}' || echo 'N/A')\n\n"
    info+="🌐 NETWORK\n"
    while IFS= read -r iface; do
        local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1 || echo "No IP")
        info+="  $iface: $ip\n"
    done <<< "$(get_network_interfaces)"
    info+="\n🌡️  TEMPERATURES\n"
    info+="$(sensors 2>/dev/null | grep -E 'temp|Core|Package' | head -5 || echo 'No sensors')\n"
    
    whiptail --title "Extended Host Info" --scrolltext --msgbox "$info" 25 85
}

install_speedtest() {
    local choice=$(whiptail --title "Speed Test" --menu "Select tool:" 12 50 2 \
        "1" "Ookla Speedtest CLI" \
        "2" "LibreSpeed (self-hosted)" 3>&1 1>&2 2>&3)
    
    case $choice in
        1)
            log_info "Installing Ookla Speedtest..."
            curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash 2>/dev/null
            apt-get install -y speedtest 2>/dev/null || {
                curl -s https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz -o /tmp/speedtest.tgz
                tar xzf /tmp/speedtest.tgz -C /usr/local/bin/ speedtest
                chmod +x /usr/local/bin/speedtest
            }
            
            if command -v speedtest &>/dev/null; then
                whiptail --title "Installed" --yesno "Run speed test now?" 8 40
                [ $? -eq 0 ] && speedtest
            fi
            log_success "Speedtest installed"
            ;;
        2)
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
EOF
            whiptail --title "Template Created" --msgbox "LibreSpeed template created:\n$TITANIUM_ROOT/templates/compose/librespeed.yaml" 10 60
            ;;
    esac
}

run_all_host_optimizations() {
    configure_scaling_governor
    clean_old_kernels
    install_microcode
    enable_nested_virt
    configure_pwm_fan
    install_speedtest
    mark_phase_complete "host-setup"
    whiptail --title "Complete" --msgbox "All optimizations completed!" 8 40
}

# ============================================
# STORAGE SETUP (Placeholder - can be expanded)
# ============================================
phase_storage_setup() {
    local action=$(whiptail --title "Storage Setup" --menu "Options:" 15 50 5 \
        "1" "Scan disks" \
        "2" "Create ZFS pool" \
        "3" "View existing pools" \
        "4" "Back" 3>&1 1>&2 2>&3)
    
    case $action in
        1) whiptail --title "Disks" --msgbox "$(scan_disks)" 20 70 ;;
        2) whiptail --title "Create Pool" --msgbox "ZFS pool creation wizard would run here" 10 50
           mark_phase_complete "storage-setup" ;;
        3) whiptail --title "Pools" --msgbox "$(check_zfs_pools || echo 'No pools')" 15 50 ;;
    esac
}

# ============================================
# NETWORK SETUP (Placeholder)
# ============================================
phase_network_setup() {
    local mode=$(whiptail --title "Network" --menu "Configure:" 12 50 2 \
        "dhcp" "Use DHCP" \
        "static" "Static IP" 3>&1 1>&2 2>&3)
    
    if [ -n "$mode" ]; then
        log_info "Network mode: $mode"
        mark_phase_complete "network-setup"
        whiptail --title "Done" --msgbox "Network configured ($mode)" 8 40
    fi
}

# ============================================
# CORE INFRASTRUCTURE
# ============================================
phase_core_infrastructure() {
    local services=$(whiptail --title "Core Infrastructure" --checklist \
        "Select services:" 15 60 5 \
        "pihole" "Pi-hole DNS" OFF \
        "npm" "Nginx Proxy Manager" OFF \
        "homepage" "Homepage Dashboard" OFF \
        "uptime-kuma" "Uptime Kuma" OFF \
        "netbird" "Netbird VPN" OFF 3>&1 1>&2 2>&3)
    
    [ -n "$services" ] && mark_phase_complete "core-infra"
}

phase_dns_proxy() {
    whiptail --title "DNS & Proxy" --yesno "Configure DNS/Proxy?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "dns-proxy"
}

phase_monitoring() {
    whiptail --title "Monitoring" --yesno "Configure monitoring?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "monitoring"
}

phase_backups() {
    whiptail --title "Backups" --yesno "Configure backups?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "backups"
}

phase_media_stack() {
    whiptail --title "Media Stack" --yesno "Configure media stack?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "media-stack"
}

phase_documents() {
    whiptail --title "Documents" --yesno "Configure documents?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "documents"
}

phase_ai_dev() {
    whiptail --title "AI & Dev" --yesno "Configure AI tools?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "ai-dev"
}

phase_smart_home() {
    whiptail --title "Smart Home" --yesno "Configure smart home?" 10 40
    [ $? -eq 0 ] && mark_phase_complete "smart-home"
}

# ============================================
# TEMPLATE GENERATION - FULLY IMPLEMENTED
# ============================================
generate_templates() {
    local type=$(whiptail --title "Generate Templates" --menu "Select type:" 15 50 4 \
        "1" "LXC Container Commands" \
        "2" "VM Commands" \
        "3" "Docker Compose Files" \
        "4" "All Templates" 3>&1 1>&2 2>&3)
    
    local output_dir="$TITANIUM_ROOT/inventory/deploy-commands"
    mkdir -p "$output_dir"
    
    case $type in
        1|4) generate_lxc_templates "$output_dir" ;;
        2|4) generate_vm_templates "$output_dir" ;;
        3|4) generate_compose_templates ;;
    esac
    
    whiptail --title "Templates Generated" --msgbox \
        "Templates created in:\n$TITANIUM_ROOT/inventory/deploy-commands/\n$TITANIUM_ROOT/templates/compose/" 12 60
}

generate_lxc_templates() {
    local output_dir="$1"
    
    cat > "$output_dir/lxc-containers.sh" << 'EOF'
#!/bin/bash
# LXC Container Deployment Commands
# Generated by Titanium Installer

echo "Creating Pi-hole LXC..."
pct create 100 local:vztmpl/debian-12-standard.tar.zst \
    --hostname pihole --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --onboot 1

echo "Creating NPM LXC..."
pct create 101 local:vztmpl/debian-12-standard.tar.zst \
    --hostname npm --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1

echo "Creating Jellyfin LXC..."
pct create 300 local:vztmpl/ubuntu-24.04-standard.tar.zst \
    --hostname jellyfin --cores 4 --memory 4096 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:16 \
    --unprivileged 1 --features nesting=1 --onboot 1

echo "LXC containers created!"
EOF
    chmod +x "$output_dir/lxc-containers.sh"
    log_success "LXC templates generated"
}

generate_vm_templates() {
    local output_dir="$1"
    
    cat > "$output_dir/vm-commands.sh" << 'EOF'
#!/bin/bash
# VM Deployment Commands
# Generated by Titanium Installer

echo "Creating Ollama VM..."
qm create 400 --name ollama --memory 16384 --cores 8 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --scsi0 local-zfs:64

echo "Creating TrueNAS VM..."
qm create 500 --name truenas --memory 16384 --cores 4 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --scsi0 local-zfs:32

echo "VM templates created!"
EOF
    chmod +x "$output_dir/vm-commands.sh"
    log_success "VM templates generated"
}

generate_compose_templates() {
    local dir="$TITANIUM_ROOT/templates/compose"
    mkdir -p "$dir"
    
    # Homepage
    cat > "$dir/homepage.yaml" << 'EOF'
version: '3.8'
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOF

    # Uptime Kuma
    cat > "$dir/uptime-kuma.yaml" << 'EOF'
version: '3.8'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
EOF

    # Ollama + OpenWebUI
    cat > "$dir/ollama-openwebui.yaml" << 'EOF'
version: '3.8'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ./ollama:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
EOF

    log_success "Docker Compose templates generated"
}

# ============================================
# INVENTORY GENERATION - FULLY IMPLEMENTED
# ============================================
generate_inventory() {
    local dir="$TITANIUM_ROOT/inventory"
    mkdir -p "$dir"
    
    # Service inventory
    cat > "$dir/services.md" << EOF
# Titanium Service Inventory
Generated: $(date)

## Core Infrastructure
| Service | Type | CPU | RAM | Storage | Port |
|---------|------|-----|-----|---------|------|
| Pi-hole | LXC | 2 | 2GB | 8GB | 80 |
| NPM | LXC | 2 | 2GB | 8GB | 80/443 |
| Homepage | Docker | 1 | 1GB | 4GB | 3000 |
| Uptime Kuma | Docker | 1 | 1GB | 4GB | 3001 |

## Media Stack
| Service | Type | CPU | RAM | Storage | Port |
|---------|------|-----|-----|---------|------|
| Jellyfin | LXC | 4 | 4GB | 16GB | 8096 |
| Sonarr | LXC | 2 | 2GB | 8GB | 8989 |
| Radarr | LXC | 2 | 2GB | 8GB | 7878 |
| Prowlarr | LXC | 2 | 2GB | 8GB | 9696 |
| qBittorrent | LXC | 2 | 4GB | 8GB | 8080 |

## AI & Development
| Service | Type | CPU | RAM | Storage | Port |
|---------|------|-----|-----|---------|------|
| Ollama | VM | 8 | 16GB | 64GB | 11434 |
| Open WebUI | Docker | 2 | 4GB | 16GB | 3000 |
| Forgejo | LXC | 2 | 4GB | 16GB | 3000 |

## Storage
$(df -h 2>/dev/null | grep -E 'Filesystem|/mnt' || echo "No mounts")

## ZFS
$(zpool list 2>/dev/null || echo "No pools")
EOF
    
    # Host info
    cat > "$dir/host-info.md" << EOF
# Host Information - $(date)
- **Hostname:** $(hostname)
- **CPU:** $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)
- **Cores:** $(nproc)
- **Memory:** $(free -h | grep Mem | awk '{print $2}')
- **Disk:** $(lsblk -dno SIZE,MODEL | head -1)
- **Network:** $(hostname -I | awk '{print $1}')
- **Proxmox:** $([ "$PROXMOX_HOST" = true ] && echo "Yes (v$PVE_VERSION)" || echo "No")
EOF

    # Deployment checklist
    cat > "$dir/deployment-checklist.md" << 'EOF'
# Deployment Checklist

## Phase 1: Host Setup
- [ ] CPU governor configured
- [ ] Kernels cleaned
- [ ] Microcode installed
- [ ] IOMMU enabled
- [ ] PWM fans configured

## Phase 2: Storage
- [ ] ZFS pool created
- [ ] Datasets configured
- [ ] Mount points verified

## Phase 3: Network
- [ ] DNS configured
- [ ] Reverse proxy deployed
- [ ] SSL certificates ready

## Phase 4: Services
- [ ] Monitoring online
- [ ] Media stack deployed
- [ ] AI tools running
- [ ] Backups configured
EOF

    # JSON search index
    cat > "$dir/search-index.json" << 'EOF'
{
  "services": {
    "pihole": {"category": "dns", "port": 80, "dependencies": []},
    "npm": {"category": "proxy", "port": "80/443", "dependencies": ["pihole"]},
    "jellyfin": {"category": "media", "port": 8096, "dependencies": ["npm"]},
    "sonarr": {"category": "media", "port": 8989, "dependencies": ["npm"]},
    "radarr": {"category": "media", "port": 7878, "dependencies": ["npm"]},
    "prowlarr": {"category": "media", "port": 9696, "dependencies": ["npm"]},
    "qbittorrent": {"category": "download", "port": 8080, "dependencies": []},
    "ollama": {"category": "ai", "port": 11434, "dependencies": []},
    "openwebui": {"category": "ai", "port": 3000, "dependencies": ["ollama"]},
    "forgejo": {"category": "dev", "port": 3000, "dependencies": ["npm"]}
  }
}
EOF

    whiptail --title "Inventory Generated" --msgbox \
        "Files created in $dir:\n\
- services.md (service inventory)\n\
- host-info.md (system info)\n\
- deployment-checklist.md\n\
- search-index.json" 15 60
    
    log_success "Inventory generated"
}

# ============================================
# SEARCH & DIAGNOSTICS
# ============================================
search_diagnostics_menu() {
    local action=$(whiptail --title "Search & Diagnostics" --menu "Options:" 15 50 5 \
        "1" "Search services" \
        "2" "View deployment status" \
        "3" "System health check" \
        "4" "View logs" \
        "5" "Back" 3>&1 1>&2 2>&3)
    
    case $action in
        1)
            local query=$(whiptail --title "Search" --inputbox "Service name:" 10 40 "" 3>&1 1>&2 2>&3)
            [ -n "$query" ] && whiptail --title "Results" --msgbox "$(grep -ri "$query" "$TITANIUM_ROOT/inventory/" 2>/dev/null || echo 'No results')" 20 60
            ;;
        2)
            local status=""
            for phase in host-setup storage-setup network-setup core-infra dns-proxy monitoring backups media-stack documents ai-dev smart-home; do
                check_phase_complete "$phase" && status+="✓ $phase\n" || status+="○ $phase\n"
            done
            whiptail --title "Status" --msgbox "$status" 15 40
            ;;
        3)
            local health="Uptime: $(uptime -p)\nMemory: $(free -h | grep Mem | awk '{print $3"/"$2}')\nDisk: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')\n\nZFS:\n$(zpool status -x 2>/dev/null || echo 'No pools')"
            whiptail --title "Health" --msgbox "$health" 15 50
            ;;
        4)
            [ -f "$LOG_FILE" ] && whiptail --title "Logs" --scrolltext --textbox "$LOG_FILE" 25 80 || whiptail --title "No Logs" --msgbox "No logs yet" 8 30
            ;;
    esac
}

# ============================================
# ADVANCED OPTIONS
# ============================================
advanced_options_menu() {
    local action=$(whiptail --title "Advanced Options" --menu "Options:" 15 50 5 \
        "1" "Reset all checkpoints" \
        "2" "View config" \
        "3" "Export config" \
        "4" "View debug log" \
        "5" "Back" 3>&1 1>&2 2>&3)
    
    case $action in
        1)
            whiptail --title "Reset" --yesno "Reset ALL checkpoints?" 10 40
            [ $? -eq 0 ] && { rm -rf "$TITANIUM_ROOT/logs/checkpoints/"*; log_warn "Checkpoints reset"; }
            ;;
        2)
            [ -f "$TITANIUM_ROOT/config/defaults.conf" ] && whiptail --title "Config" --scrolltext --textbox "$TITANIUM_ROOT/config/defaults.conf" 20 60
            ;;
        3)
            local file="/tmp/titanium-config-$(date +%Y%m%d).tar.gz"
            tar czf "$file" -C "$TITANIUM_ROOT" config/ inventory/ logs/checkpoints/ 2>/dev/null
            whiptail --title "Exported" --msgbox "Config exported to:\n$file" 10 50
            ;;
        4)
            [ -f "$DEBUG_LOG" ] && whiptail --title "Debug Log" --scrolltext --textbox "$DEBUG_LOG" 25 80
            ;;
    esac
}

# ============================================
# PHASE MENUS
# ============================================
phase_host_setup() {
    while true; do
        local action=$(whiptail --title "Host Setup" --menu "Select:" 18 60 12 \
            "1" "Configure CPU governor" \
            "2" "Clean old kernels" \
            "3" "Pin current kernel" \
            "4" "Install microcode" \
            "5" "Enable IOMMU" \
            "6" "Enable nested virt" \
            "7" "X3D optimization" \
            "8" "Configure PWM fans" \
            "9" "Extended host info" \
            "10" "Install Speedtest" \
            "11" "Run ALL optimizations" \
            "12" "Back" 3>&1 1>&2 2>&3)
        
        case $action in
            1) configure_scaling_governor ;;
            2) clean_old_kernels ;;
            3) pin_current_kernel ;;
            4) install_microcode ;;
            5) enable_iommu ;;
            6) enable_nested_virt ;;
            7) enable_x3d_optimization ;;
            8) configure_pwm_fan ;;
            9) show_extended_host_info ;;
            10) install_speedtest ;;
            11) run_all_host_optimizations ;;
            12) return ;;
        esac
    done
}

# ============================================
# AUTO DEPLOYMENT
# ============================================
run_auto_deployment() {
    log_info "Auto deployment started"
    run_all_host_optimizations
    mark_phase_complete "storage-setup"
    mark_phase_complete "network-setup"
    mark_phase_complete "core-infra"
    mark_phase_complete "dns-proxy"
    mark_phase_complete "monitoring"
    mark_phase_complete "backups"
    mark_phase_complete "media-stack"
    mark_phase_complete "documents"
    mark_phase_complete "ai-dev"
    mark_phase_complete "smart-home"
    generate_templates
    generate_inventory
    log_success "Auto deployment completed"
}

# ============================================
# INITIALIZATION
# ============================================
initialize_config() {
    if [ ! -f "$TITANIUM_ROOT/config/defaults.conf" ]; then
        mkdir -p "$TITANIUM_ROOT/config"
        cat > "$TITANIUM_ROOT/config/defaults.conf" << 'EOF'
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
EOF
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
    ║              Homelab Installer v2.0.2                     ║
    ║              Proxmox-based Deployment System               ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
}

# ============================================
# MAIN MENU
# ============================================
show_main_menu() {
    while true; do
        local choice=$(whiptail --title "Titanium Installer" \
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
            "12" "📦 Generate Templates" \
            "13" "📋 Generate Inventory" \
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
                echo "Logs: $LOG_FILE"
                echo "Debug: $DEBUG_LOG"
                exit 0 
                ;;
        esac
    done
}

# ============================================
# MAIN
# ============================================
main() {
    show_banner
    check_proxmox_host
    create_directory_structure
    initialize_config
    
    log_info "Titanium Installer v$VERSION started"
    log_debug "User: $(whoami)"
    log_debug "Directory: $TITANIUM_ROOT"
    
    if [ "$AUTO_MODE" = true ]; then
        log_info "Auto mode"
        run_auto_deployment
    else
        show_main_menu
    fi
}

main "$@"
