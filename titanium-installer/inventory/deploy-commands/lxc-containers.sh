#!/bin/bash
# LXC Container Deployment Commands
# Generated: $(date)

# Example: Pi-hole
# pct create 100 local:vztmpl/debian-12-standard.tar.zst \
#     --hostname pihole --cores 2 --memory 2048 \
#     --net0 name=eth0,bridge=vmbr0,ip=dhcp \
#     --storage local-zfs --rootfs local-zfs:8 \
#     --unprivileged 1 --onboot 1

