#!/usr/bin/env bash
# ============================================================================
# netboost/lib/dns.sh
# DNS optimization: benchmarking and resolver configuration.
#
# Why this matters:
#   Default DNS from the kost router is often the ISP's resolver, which can
#   be slow and overloaded. Switching to a low-latency public resolver
#   (Cloudflare, Google, Quad9) reduces the time between typing a URL and
#   the first byte arriving.
# ============================================================================

readonly DNS_PROVIDERS=(
    "cloudflare:1.1.1.1:1.0.0.1"
    "google:8.8.8.8:8.8.4.4"
    "quad9:9.9.9.9:149.112.112.112"
)

measure_dns_latency() {
    local server="$1"
    local domain="${2:-google.com}"

    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s%N)
    nslookup "$domain" "$server" >/dev/null 2>&1
    end_ns=$(date +%s%N)

    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    echo "$elapsed_ms"
}

benchmark_dns_providers() {
    log_header "DNS Provider Benchmark"
    log_info "Resolving google.com against each provider..."
    echo ""

    local fastest_name=""
    local fastest_time=99999

    for provider in "${DNS_PROVIDERS[@]}"; do
        IFS=':' read -r name primary secondary <<< "$provider"

        local time_ms
        time_ms=$(measure_dns_latency "$primary")

        local color="$GREEN"
        if   (( time_ms > 100 )); then color="$RED"
        elif (( time_ms > 50  )); then color="$YELLOW"
        fi

        printf "  %-14s %-16s ${color}%d ms${NC}\n" "$name" "$primary" "$time_ms"

        if (( time_ms < fastest_time )); then
            fastest_time=$time_ms
            fastest_name=$name
        fi
    done

    echo ""
    log_info "Fastest: ${BOLD}${fastest_name}${NC} (${fastest_time}ms)"

    # Compare against current resolver
    local current_dns
    current_dns=$(grep "nameserver" /etc/resolv.conf 2>/dev/null \
        | grep -v "127.0.0" | head -n 1 | awk '{print $2}')
    if [[ -z "$current_dns" ]]; then
        current_dns="127.0.0.53"
    fi

    local current_time
    current_time=$(measure_dns_latency "$current_dns")
    print_kv "Current ($current_dns)" "${current_time}ms"
}

optimize_dns() {
    require_root

    log_header "DNS Optimization"

    # Detect DNS management method
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        log_info "systemd-resolved is active. Configuring via resolvectl."

        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface
            iface="$WIFI_INTERFACE"
        fi

        if [[ -z "$iface" ]]; then
            log_error "Cannot determine Wi-Fi interface for DNS config."
            return 1
        fi

        resolvectl dns "$iface" 1.1.1.1 1.0.0.1 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "DNS on $iface set to Cloudflare (1.1.1.1, 1.0.0.1)."
        else
            log_error "resolvectl failed. Try manually: resolvectl dns $iface 1.1.1.1 1.0.0.1"
            return 1
        fi

        # Optionally enable DNS over TLS for privacy
        resolvectl dnsovertls "$iface" opportunistic 2>/dev/null
        log_info "DNS-over-TLS set to opportunistic mode."
    else
        log_warn "systemd-resolved not active. Direct /etc/resolv.conf editing is risky."
        log_warn "Skipping DNS change. Manually edit /etc/resolv.conf if desired."
    fi
}

get_dns_status() {
    log_header "DNS Status"

    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        print_kv "Manager" "systemd-resolved"

        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface
            iface="$WIFI_INTERFACE"
        fi

        if [[ -n "$iface" ]]; then
            local dns_info
            dns_info=$(resolvectl status "$iface" 2>/dev/null)
            local servers
            servers=$(echo "$dns_info" | grep "DNS Servers" | sed 's/.*: //')
            print_kv "DNS Servers ($iface)" "${servers:-default (DHCP)}"

            local dot_status
            dot_status=$(echo "$dns_info" | grep "DNSOverTLS" | sed 's/.*: //')
            print_kv "DNS-over-TLS" "${dot_status:-no}"
        fi
    else
        print_kv "Manager" "resolv.conf"
        grep "nameserver" /etc/resolv.conf 2>/dev/null | while read -r _ server; do
            print_kv "Nameserver" "$server"
        done
    fi
}

reset_dns() {
    require_root

    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface
            iface="$WIFI_INTERFACE"
        fi

        if [[ -n "$iface" ]]; then
            resolvectl revert "$iface" 2>/dev/null
            log_success "DNS on $iface reverted to DHCP defaults."
        fi
    else
        log_warn "No automated DNS revert available. Check /etc/resolv.conf manually."
    fi
}
