#!/bin/bash
# titanium-installer/inventory/generate-inventory.sh
# Automated inventory generation

generate_inventory() {
    local inventory_dir="$TITANIUM_ROOT/inventory"
    mkdir -p "$inventory_dir"

    # Service inventory
    cat > "$inventory_dir/services.md" << 'EOF'
# Titanium Service Inventory
Generated: $(date)

## Core Infrastructure
| Service | Type | IP | Port | Status |
|---------|------|----|------|--------|
| Pi-hole | LXC | - | 80 | Planned |
| Nginx Proxy Manager | LXC | - | 80/443 | Planned |
| Homepage | LXC | - | 3000 | Planned |
| Uptime Kuma | LXC | - | 3001 | Planned |
| Netbird | LXC | - | 33073 | Planned |

## Media Stack
| Service | Type | IP | Port | Status |
|---------|------|----|------|--------|
| Jellyfin | LXC | - | 8096 | Planned |
| Sonarr | LXC | - | 8989 | Planned |
| Radarr | LXC | - | 7878 | Planned |
| Prowlarr | LXC | - | 9696 | Planned |
| qBittorrent | LXC | - | 8080 | Planned |

## AI & Development
| Service | Type | IP | Port | Status |
|---------|------|----|------|--------|
| Ollama | VM | - | 11434 | Planned |
| Open WebUI | LXC | - | 3000 | Planned |
| Forgejo | LXC | - | 3000 | Planned |

## Documents & Notes
| Service | Type | IP | Port | Status |
|---------|------|----|------|--------|
| Paperless-ngx | LXC | - | 8000 | Planned |
| Stirling-PDF | LXC | - | 8080 | Planned |
EOF

    # Host inventory
    cat > "$inventory_dir/host-info.md" << EOF
# Host Information
Generated: $(date)

## System
- Hostname: $(hostname)
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)
- Kernel: $(uname -r)
- CPU: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)
- Memory: $(free -h | grep Mem | awk '{print $2}')
- Proxmox: $([ "$PROXMOX_HOST" = true ] && echo "Yes" || echo "No")

## Storage
$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part")

## Network
$(ip -4 addr show | grep inet | grep -v 127.0.0.1)

## ZFS Pools
$(zpool list 2>/dev/null || echo "No ZFS pools found")
EOF

    # Deployment checklist
    cat > "$inventory_dir/deployment-checklist.md" << 'EOF'
# Deployment Checklist

## Phase 1: Host Setup
- [ ] Proxmox installation verified
- [ ] post-pve-install script executed
- [ ] CPU governor configured
- [ ] Kernel cleaned and pinned
- [ ] IOMMU enabled (if needed)
- [ ] Storage configured
- [ ] Network configured

## Phase 2: Core Infrastructure
- [ ] DNS (Pi-hole) deployed
- [ ] Reverse proxy (NPM) deployed
- [ ] SSL certificates configured
- [ ] Monitoring online
- [ ] Backups configured

## Phase 3: Services
- [ ] Media stack deployed
- [ ] Document management deployed
- [ ] AI tools deployed
- [ ] Smart home configured
- [ ] Network tools online

## Phase 4: Verification
- [ ] All services reachable
- [ ] Backups verified
- [ ] Monitoring alerts configured
- [ ] Documentation updated
EOF

    # Searchable index
    cat > "$inventory_dir/search-index.json" << 'EOF'
{
  "services": {
    "pihole": {"category": "dns", "port": 80, "dependencies": []},
    "npm": {"category": "proxy", "port": "80/443", "dependencies": ["pihole"]},
    "jellyfin": {"category": "media", "port": 8096, "dependencies": ["npm"]},
    "sonarr": {"category": "media", "port": 8989, "dependencies": ["npm", "qbittorrent"]},
    "radarr": {"category": "media", "port": 7878, "dependencies": ["npm", "qbittorrent"]},
    "prowlarr": {"category": "media", "port": 9696, "dependencies": ["npm"]},
    "qbittorrent": {"category": "download", "port": 8080, "dependencies": []},
    "paperless": {"category": "documents", "port": 8000, "dependencies": ["npm"]},
    "ollama": {"category": "ai", "port": 11434, "dependencies": []},
    "forgejo": {"category": "dev", "port": 3000, "dependencies": ["npm"]}
  },
  "dependencies": {
    "pihole": [],
    "npm": ["pihole"],
    "monitoring": ["npm"],
    "media": ["npm"],
    "documents": ["npm"],
    "ai": ["npm"],
    "dev": ["npm"]
  }
}
EOF

    log_success "Inventory files generated in: $inventory_dir"
}
