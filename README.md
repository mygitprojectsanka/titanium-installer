# titanium-installer
Proxmox Installer Script

Core Features Built In:
1. Auto-detection of Proxmox host with non-Proxmox warning
2. ZFS Wizard with disk scanning, by-id paths, NVMe/SATA detection
3. Network Setup with DHCP/static options
4. Checkpoint System for resumable deployment
5. Template Generator for LXC/VM commands
6. Inventory Generator with service tracking
7. Restore Procedures for disaster recovery

Directory Structure:
titanium-installer/
├── launch.sh                    # Main entry point
├── lib/                         # Core libraries
│   ├── common.sh               # Utilities & logging
│   ├── ui.sh                   # Premium UI components
│   ├── zfs-wizard.sh           # Advanced ZFS configuration
│   ├── network-setup.sh        # Network configuration
│   └── checkpoint.sh           # Phase tracking
├── config/                      # Configuration files
│   ├── defaults.conf           # All default values
│   ├── storage-layout.conf     # Storage mappings
│   └── service-ports.conf      # Port assignments
├── templates/                   # Deployment templates
│   ├── lxc-profiles/
│   ├── vm-profiles/
│   └── compose/
├── inventory/                   # Generated inventory
├── logs/                        # Deployment logs
├── scripts/                     # Utility scripts
└── restore/                     # Recovery procedures

