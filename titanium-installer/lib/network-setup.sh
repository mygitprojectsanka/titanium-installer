#!/bin/bash
# titanium-installer/lib/network-setup.sh
# Network configuration wizard with DHCP/static options

network_configuration_wizard() {
    local interfaces=$(get_network_interfaces)
    local options=()

    while IFS= read -r iface; do
        local ip_info=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        [ -z "$ip_info" ] && ip_info="Not configured"
        options+=("$iface" "IP: $ip_info")
    done <<< "$interfaces"

    local selected_iface=$(show_radiolist \
        "Network Interface" \
        "Select network interface:" \
        15 70 5 \
        "${options[@]}")

    [ -z "$selected_iface" ] && return

    local mode=$(show_radiolist \
        "IP Configuration" \
        "Select IP configuration mode:" \
        15 60 3 \
        "dhcp" "Dynamic (DHCP)" "ON" \
        "static" "Static IP" "OFF" \
        "manual" "Manual configuration only" "OFF")

    case $mode in
        dhcp)
            configure_dhcp "$selected_iface"
            ;;
        static)
            configure_static_ip "$selected_iface"
            ;;
        manual)
            manual_network_config "$selected_iface"
            ;;
    esac
}

configure_dhcp() {
    local iface=$1
    cat > "/etc/network/interfaces.d/${iface}" << EOF
auto ${iface}
iface ${iface} inet dhcp
EOF
    show_message "DHCP Configured" "Interface $iface configured for DHCP" "success"
}

configure_static_ip() {
    local iface=$1

    local ip=$(show_input "Static IP" "Enter IP address (CIDR):" "192.168.1.100/24")
    local gateway=$(show_input "Gateway" "Enter gateway IP:" "192.168.1.1")
    local dns=$(show_input "DNS Servers" "Enter DNS servers (space-separated):" "1.1.1.1 8.8.8.8")

    cat > "/etc/network/interfaces.d/${iface}" << EOF
auto ${iface}
iface ${iface} inet static
    address ${ip}
    gateway ${gateway}
    dns-nameservers ${dns}
EOF

    show_message "Static IP Configured" \
        "Configuration:\nInterface: $iface\nIP: $ip\nGateway: $gateway\nDNS: $dns" \
        "info"
}
