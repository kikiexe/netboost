#!/usr/bin/env bash
# ============================================================================
# netboost/lib/wifi.sh
# Wi-Fi adapter detection and optimization.
#
# Key optimizations:
#   - Disable power save to eliminate latency spikes caused by the adapter
#     entering low-power sleep between transmissions.
#   - Report signal quality and link rates for diagnostic context.
# ============================================================================

WIFI_INTERFACE=""

detect_wifi_interface() {
    WIFI_INTERFACE=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | head -n 1)
    if [[ -z "$WIFI_INTERFACE" ]]; then
        log_error "No wireless interface detected."
        return 1
    fi
    return 0
}

get_wifi_status() {
    detect_wifi_interface || return 1

    local link_info
    link_info=$(iw dev "$WIFI_INTERFACE" link 2>/dev/null)

    if echo "$link_info" | grep -q "Not connected"; then
        log_warn "Wi-Fi interface $WIFI_INTERFACE is not connected."
        return 1
    fi

    local ssid signal rx_bitrate tx_bitrate frequency bssid
    ssid=$(echo "$link_info" | grep "SSID:" | awk '{$1=""; print $0}' | xargs)
    signal=$(echo "$link_info" | grep "signal:" | awk '{print $2, $3}')
    rx_bitrate=$(echo "$link_info" | grep "rx bitrate:" | sed 's/.*rx bitrate: //')
    tx_bitrate=$(echo "$link_info" | grep "tx bitrate:" | sed 's/.*tx bitrate: //')
    frequency=$(echo "$link_info" | grep "freq:" | awk '{print $2}')
    bssid=$(echo "$link_info" | grep "Connected to" | awk '{print $3}')

    local power_save
    power_save=$(iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | awk '{print $3}')

    # Determine signal quality label
    local signal_num="${signal%% *}"
    signal_num="${signal_num//-/}"
    local quality="UNKNOWN"
    if [[ -n "$signal_num" ]] && [[ "$signal_num" =~ ^[0-9]+$ ]]; then
        if   (( signal_num < 50 )); then quality="${GREEN}EXCELLENT${NC}"
        elif (( signal_num < 60 )); then quality="${GREEN}GOOD${NC}"
        elif (( signal_num < 70 )); then quality="${YELLOW}FAIR${NC}"
        elif (( signal_num < 80 )); then quality="${YELLOW}WEAK${NC}"
        else                             quality="${RED}POOR${NC}"
        fi
    fi

    log_header "Wi-Fi Status ($WIFI_INTERFACE)"
    print_kv "SSID"          "$ssid"
    print_kv "BSSID"         "$bssid"
    print_kv "Frequency"     "${frequency} MHz"
    print_kv "Signal"        "$signal"
    echo -e "  ${DIM}$(printf '%-28s' "Quality")${NC} $quality"
    print_kv "RX Bitrate"    "$rx_bitrate"
    print_kv "TX Bitrate"    "$tx_bitrate"
    print_kv "Power Save"    "$power_save"
}

optimize_wifi() {
    require_root
    detect_wifi_interface || return 1

    log_header "Wi-Fi Adapter Optimization"

    # 1. Disable power save
    local current_ps
    current_ps=$(iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | awk '{print $3}')
    if [[ "$current_ps" == "on" ]]; then
        iw dev "$WIFI_INTERFACE" set power_save off 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Power save disabled."
        else
            log_error "Failed to disable power save."
        fi
    else
        log_success "Power save already disabled."
    fi

    # 2. Report current regulatory domain for awareness
    if command -v iw &>/dev/null; then
        local reg_domain
        reg_domain=$(iw reg get 2>/dev/null | grep "country" | head -n 1 | awk '{print $2}' | tr -d ':')
        log_info "Regulatory domain: ${reg_domain:-unknown}"
    fi
}

reset_wifi() {
    require_root
    detect_wifi_interface || return 1

    iw dev "$WIFI_INTERFACE" set power_save on 2>/dev/null
    log_success "Power save re-enabled (default)."
}
