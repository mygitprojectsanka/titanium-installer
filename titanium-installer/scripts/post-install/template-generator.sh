#!/bin/bash
# titanium-installer/scripts/post-install/template-generator.sh
# LXC/VM template command generator

generate_deployment_templates() {
    local output_dir="$TITANIUM_ROOT/inventory/deploy-commands"
    mkdir -p "$output_dir"

    # Core Infrastructure
    cat > "$output_dir/01-core-infrastructure.sh" << 'EOF'
#!/bin/bash
# Core Infrastructure Deployment Commands

# Homepage Dashboard
pct create 200 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname homepage --cores 1 --memory 1024 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:4 \
    --unprivileged 1 --features nesting=1 --onboot 1

# Uptime Kuma
pct create 201 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname uptime-kuma --cores 1 --memory 1024 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:4 \
    --unprivileged 1 --features nesting=1 --onboot 1

# Netbird
pct create 202 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname netbird --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1
EOF

    # Media Stack
    cat > "$output_dir/02-media-stack.sh" << 'EOF'
#!/bin/bash
# Media Stack Deployment Commands

# Jellyfin Server
pct create 300 local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst \
    --hostname jellyfin --cores 4 --memory 4096 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:16 \
    --unprivileged 1 --features nesting=1 --onboot 1
pct set 300 --mp0 /mnt/media,mp=/media

# Sonarr
pct create 301 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname sonarr --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1
pct set 301 --mp0 /mnt/media,mp=/media --mp1 /mnt/downloads,mp=/downloads

# Radarr
pct create 302 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname radarr --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1
pct set 302 --mp0 /mnt/media,mp=/media --mp1 /mnt/downloads,mp=/downloads

# Prowlarr
pct create 303 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname prowlarr --cores 2 --memory 2048 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1

# qBittorrent
pct create 304 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname qbittorrent --cores 2 --memory 4096 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:8 \
    --unprivileged 1 --features nesting=1 --onboot 1
pct set 304 --mp0 /mnt/downloads,mp=/downloads
EOF

    # AI Stack
    cat > "$output_dir/03-ai-stack.sh" << 'EOF'
#!/bin/bash
# AI & Development Stack Deployment Commands

# Ollama Server (VM for GPU passthrough)
qm create 400 --name ollama --memory 16384 --cores 8 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --scsi0 local-zfs:64

# Open WebUI
pct create 401 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname openwebui --cores 2 --memory 4096 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:16 \
    --unprivileged 1 --features nesting=1 --onboot 1

# Forgejo (Git)
pct create 402 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname forgejo --cores 2 --memory 4096 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage local-zfs --rootfs local-zfs:16 \
    --unprivileged 1 --features nesting=1 --onboot 1
EOF

    chmod +x "$output_dir"/*.sh
    log_success "Deployment templates generated in: $output_dir"
}

# VM Template Generator
generate_vm_commands() {
    mkdir -p "$TITANIUM_ROOT/templates/vm-profiles"

    # TrueNAS VM Template
    cat > "$TITANIUM_ROOT/templates/vm-profiles/truenas.conf" << 'EOF'
# TrueNAS VM Configuration
qm create 500 \
    --name truenas \
    --memory 16384 \
    --cores 4 \
    --sockets 1 \
    --cpu host \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --scsi0 local-zfs:32 \
    --ide2 local:iso/TrueNAS-SCALE.iso,media=cdrom \
    --ostype l26 \
    --machine q35 \
    --bios ovmf \
    --efidisk0 local-zfs:4,format=raw
EOF

    # Windows VM Template
    cat > "$TITANIUM_ROOT/templates/vm-profiles/windows.conf" << 'EOF'
# Windows VM Configuration
qm create 600 \
    --name windows \
    --memory 8192 \
    --cores 4 \
    --sockets 1 \
    --cpu host \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --scsi0 local-zfs:64 \
    --ide2 local:iso/Win11.iso,media=cdrom \
    --ide3 local:iso/virtio-win.iso,media=cdrom \
    --ostype win11 \
    --machine q35 \
    --bios ovmf \
    --efidisk0 local-zfs:4,format=raw \
    --tpmstate0 local-zfs:4,version=v2.0
EOF
}
