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
readonly WIFI_BACKUP_FILE="${NETBOOST_STATE_DIR}/wifi_backup.conf"
readonly WIFI_TXPOWER_BACKUP_FILE="${NETBOOST_STATE_DIR}/wifi_txpower_backup.conf" # Legacy cleanup path

detect_wifi_interface() {
    WIFI_INTERFACE=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | head -n 1 || true)
    if [[ -z "$WIFI_INTERFACE" ]]; then
        log_error "No wireless interface detected."
        return 1
    fi
    return 0
}

get_wifi_status() {
    detect_wifi_interface || return 1

    local link_info
    link_info=$(iw dev "$WIFI_INTERFACE" link 2>/dev/null || true)

    if echo "$link_info" | grep -q "Not connected"; then
        log_warn "Wi-Fi interface $WIFI_INTERFACE is not connected."
        return 1
    fi

    local ssid signal rx_bitrate tx_bitrate frequency bssid
    ssid=$(echo "$link_info" | grep "SSID:" | awk '{$1=""; print $0}' | xargs || true)
    signal=$(echo "$link_info" | grep "signal:" | awk '{print $2, $3}' || true)
    rx_bitrate=$(echo "$link_info" | grep "rx bitrate:" | sed 's/.*rx bitrate: //' || true)
    tx_bitrate=$(echo "$link_info" | grep "tx bitrate:" | sed 's/.*tx bitrate: //' || true)
    frequency=$(echo "$link_info" | grep "freq:" | awk '{print $2}' || true)
    bssid=$(echo "$link_info" | grep "Connected to" | awk '{print $3}' || true)

    local power_save
    power_save=$(iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | awk '{print $3}' || true)

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

    local tx_power
    tx_power=$(iw dev "$WIFI_INTERFACE" info 2>/dev/null | grep "txpower" | awk '{print $2, $3}' || true)
    print_kv "TX Power (Diagnostics)" "${tx_power:-unknown}"
}

optimize_wifi() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        detect_wifi_interface || return 1
        log_header "Wi-Fi Adapter Optimization [DRY RUN]"
        log_info "Would disable power save on interface: $WIFI_INTERFACE"
        return 0
    fi

    require_root
    detect_wifi_interface || return 1

    log_header "Wi-Fi Adapter Optimization"

    # 1. Disable power save and backup original state
    local current_ps
    current_ps=$(iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | awk '{print $3}' || true)
    
    if [[ -n "$current_ps" ]]; then
        ensure_backup_dir
        if [[ ! -f "$WIFI_BACKUP_FILE" ]]; then
            echo "$current_ps" > "$WIFI_BACKUP_FILE"
            log_info "Original Wi-Fi power save state ($current_ps) saved to $WIFI_BACKUP_FILE"
        fi
    fi

    if [[ "$current_ps" == "on" ]]; then
        iw dev "$WIFI_INTERFACE" set power_save off 2>/dev/null || true
        # Verify if it was successfully changed
        local check_ps
        check_ps=$(iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | awk '{print $3}' || true)
        if [[ "$check_ps" == "off" ]]; then
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
        reg_domain=$(iw reg get 2>/dev/null | grep "country" | head -n 1 | awk '{print $2}' | tr -d ':' || true)
        log_info "Regulatory domain: ${reg_domain:-unknown}"
    fi
}

reset_wifi() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        detect_wifi_interface || return 1
        log_header "Wi-Fi Adapter Reset [DRY RUN]"
        log_info "Would restore original Wi-Fi power save state from $WIFI_BACKUP_FILE if it exists, or default to 'on'"
        log_info "Would clean up legacy TX power backup file $WIFI_TXPOWER_BACKUP_FILE if it exists"
        return 0
    fi

    require_root
    detect_wifi_interface || return 1

    # 1. Restore power save state
    local target_ps="on"
    if [[ -f "$WIFI_BACKUP_FILE" ]]; then
        target_ps=$(cat "$WIFI_BACKUP_FILE" | tr -d '[:space:]')
        rm -f "$WIFI_BACKUP_FILE"
    fi
    iw dev "$WIFI_INTERFACE" set power_save "$target_ps" 2>/dev/null || true
    log_success "Power save restored to original state: $target_ps"

    # 2. Clean up legacy TX power backup file if present
    if [[ -f "$WIFI_TXPOWER_BACKUP_FILE" ]]; then
        rm -f "$WIFI_TXPOWER_BACKUP_FILE"
        log_success "Legacy Wi-Fi TX power backup file removed."
    fi
}
