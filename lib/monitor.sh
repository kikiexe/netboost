#!/usr/bin/env bash
# ============================================================================
# netboost/lib/monitor.sh
# Real-time network quality monitoring dashboard.
#
# Displays a live table with:
#   - Timestamp
#   - Wi-Fi signal strength (dBm)
#   - Latency to default gateway (local Wi-Fi quality indicator)
#   - Latency to 8.8.8.8 (internet quality indicator)
#   - RX/TX throughput (bytes/sec from kernel counters)
#   - Overall quality label
# ============================================================================

monitor_network() {
    local interval="${1:-3}"

    local iface="$WIFI_INTERFACE"
    if [[ -z "$iface" ]]; then
        detect_wifi_interface
        iface="$WIFI_INTERFACE"
    fi

    if [[ -z "$iface" ]]; then
        log_error "No Wi-Fi interface found."
        return 1
    fi

    local gw
    gw=$(ip route | grep default | awk '{print $3}' | head -n 1)

    echo ""
    log_info "Monitoring ${BOLD}${iface}${NC} every ${interval}s. Press ${BOLD}Ctrl+C${NC} to stop."
    if [[ -n "$gw" ]]; then
        log_info "Gateway: $gw"
    fi
    echo ""

    printf "${BOLD}%-10s  %-11s  %-13s  %-13s  %-14s  %-14s  %-10s${NC}\n" \
        "TIME" "SIGNAL" "GW LATENCY" "DNS LATENCY" "RX RATE" "TX RATE" "QUALITY"
    printf "%s\n" "$(printf '%.0s-' {1..95})"

    # Initialize previous byte counters
    local prev_rx prev_tx
    prev_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
    prev_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)

    trap 'echo ""; log_info "Monitoring stopped."; return 0' INT

    while true; do
        sleep "$interval"

        # Signal strength
        local signal
        signal=$(iw dev "$iface" link 2>/dev/null | grep "signal:" | awk '{print $2}')

        # Latency to gateway (1 ping, 2s timeout)
        local gw_latency="N/A"
        if [[ -n "$gw" ]]; then
            gw_latency=$(ping -c 1 -W 2 "$gw" 2>/dev/null \
                | grep "time=" | sed 's/.*time=//;s/ *$//')
            [[ -z "$gw_latency" ]] && gw_latency="${RED}TIMEOUT${NC}"
        fi

        # Latency to external DNS
        local ext_latency
        ext_latency=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null \
            | grep "time=" | sed 's/.*time=//;s/ *$//')
        [[ -z "$ext_latency" ]] && ext_latency="${RED}TIMEOUT${NC}"

        # Throughput from kernel byte counters
        local curr_rx curr_tx
        curr_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        curr_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)

        local rx_bps=$(( (curr_rx - prev_rx) / interval ))
        local tx_bps=$(( (curr_tx - prev_tx) / interval ))
        prev_rx=$curr_rx
        prev_tx=$curr_tx

        # Format throughput with appropriate unit
        local rx_fmt tx_fmt
        rx_fmt=$(format_bytes_per_sec "$rx_bps")
        tx_fmt=$(format_bytes_per_sec "$tx_bps")

        # Signal quality classification
        local quality quality_color
        local signal_abs="${signal//-/}"
        if [[ -n "$signal_abs" ]] && [[ "$signal_abs" =~ ^[0-9]+$ ]]; then
            if   (( signal_abs < 50 )); then quality="EXCELLENT"; quality_color="$GREEN"
            elif (( signal_abs < 60 )); then quality="GOOD";      quality_color="$GREEN"
            elif (( signal_abs < 70 )); then quality="FAIR";      quality_color="$YELLOW"
            elif (( signal_abs < 80 )); then quality="WEAK";      quality_color="$YELLOW"
            else                             quality="POOR";      quality_color="$RED"
            fi
        else
            quality="???"
            quality_color="$DIM"
        fi

        local timestamp
        timestamp=$(date +%H:%M:%S)

        printf "%-10s  %-11s  %-13s  %-13s  %-14s  %-14s  ${quality_color}%-10s${NC}\n" \
            "$timestamp" \
            "${signal} dBm" \
            "$gw_latency" \
            "$ext_latency" \
            "$rx_fmt" \
            "$tx_fmt" \
            "$quality"
    done
}

format_bytes_per_sec() {
    local bps="$1"

    if   (( bps >= 1048576 )); then
        echo "$(echo "scale=1; $bps / 1048576" | bc) MB/s"
    elif (( bps >= 1024 )); then
        echo "$(echo "scale=1; $bps / 1024" | bc) KB/s"
    else
        echo "${bps} B/s"
    fi
}
