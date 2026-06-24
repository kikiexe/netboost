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
    if nslookup "$domain" "$server" >/dev/null 2>&1; then
        end_ns=$(date +%s%N)
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
        echo "$elapsed_ms"
    else
        echo "999"
    fi
}

benchmark_dns_providers() {
    log_header "DNS Provider Benchmark"
    log_info "Resolving multiple domains (3 queries each) against each provider to calculate average latency..."
    echo ""

    local domains=(
        "google.com"
        "cloudflare.com"
        "wikipedia.org"
    )
    local num_queries=3

    local fastest_name=""
    local fastest_time=99999

    for provider in "${DNS_PROVIDERS[@]}"; do
        IFS=':' read -r name primary secondary <<< "$provider"

        local total_time=0
        local success_count=0

        for domain in "${domains[@]}"; do
            for ((i=1; i<=num_queries; i++)); do
                local time_ms
                time_ms=$(measure_dns_latency "$primary" "$domain")
                if (( time_ms < 999 )); then
                    total_time=$(( total_time + time_ms ))
                    success_count=$(( success_count + 1 ))
                fi
            done
        done

        local avg_time=999
        if (( success_count > 0 )); then
            avg_time=$(( total_time / success_count ))
        fi

        local color="$GREEN"
        if   (( avg_time > 100 )); then color="$RED"
        elif (( avg_time > 50  )); then color="$YELLOW"
        fi

        local label_ms="${avg_time} ms"
        if (( avg_time == 999 )); then
            label_ms="TIMEOUT"
        fi

        printf "  %-14s %-16s ${color}%s${NC} (avg of %d successful queries)\n" \
            "$name" "$primary" "$label_ms" "$success_count"

        if (( avg_time < fastest_time )); then
            fastest_time=$avg_time
            fastest_name=$name
        fi
    done

    echo ""
    if (( fastest_time < 999 )); then
        log_info "Fastest: ${BOLD}${fastest_name}${NC} (${fastest_time}ms avg)"
    else
        log_info "All providers timed out."
    fi

    # Compare against current resolver
    local current_dns
    current_dns=$(awk '$1 == "nameserver" && $2 !~ /^127\.0\.0/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)
    if [[ -z "$current_dns" ]]; then
        current_dns="127.0.0.53"
    fi

    local current_total_time=0
    local current_success_count=0

    for domain in "${domains[@]}"; do
        for ((i=1; i<=num_queries; i++)); do
            local time_ms
            time_ms=$(measure_dns_latency "$current_dns" "$domain")
            if (( time_ms < 999 )); then
                current_total_time=$(( current_total_time + time_ms ))
                current_success_count=$(( current_success_count + 1 ))
            fi
        done
    done

    local current_avg_time=999
    if (( current_success_count > 0 )); then
        current_avg_time=$(( current_total_time / current_success_count ))
    fi

    local current_label_ms="${current_avg_time}ms"
    if (( current_avg_time == 999 )); then
        current_label_ms="TIMEOUT"
    fi

    print_kv "Current ($current_dns)" "$current_label_ms"
}

optimize_dns() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface || return 1
            iface="$WIFI_INTERFACE"
        fi
        log_header "DNS Optimization [DRY RUN]"
        if systemctl is-active systemd-resolved >/dev/null 2>&1; then
            log_info "systemd-resolved is active. Would configure resolvectl on $iface"
        else
            log_info "systemd-resolved is not active. Would skip resolv.conf changes"
        fi
        return 0
    fi

    require_root

    log_header "DNS Optimization"

    # Detect DNS management method
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        log_info "systemd-resolved is active. Configuring via resolvectl."

        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface || return 1
            iface="$WIFI_INTERFACE"
        fi

        if [[ -z "$iface" ]]; then
            log_error "Cannot determine Wi-Fi interface for DNS config."
            return 1
        fi

        resolvectl dns "$iface" 1.1.1.1 1.0.0.1 2>/dev/null || true
        # Verify
        local check_dns
        check_dns=$(resolvectl status "$iface" 2>/dev/null | grep "DNS Servers" | sed 's/.*: //' || true)
        if [[ "$check_dns" =~ "1.1.1.1" ]]; then
            log_success "DNS on $iface set to Cloudflare (1.1.1.1, 1.0.0.1)."
        else
            log_error "resolvectl configuration check failed."
            return 1
        fi

        # Optionally enable DNS over TLS for privacy
        resolvectl dnsovertls "$iface" opportunistic 2>/dev/null || true
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
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface || return 1
            iface="$WIFI_INTERFACE"
        fi
        log_header "DNS Reset [DRY RUN]"
        log_info "Would revert resolvectl configuration on: $iface"
        return 0
    fi

    require_root

    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        local iface="$WIFI_INTERFACE"
        if [[ -z "$iface" ]]; then
            detect_wifi_interface || return 1
            iface="$WIFI_INTERFACE"
        fi

        if [[ -n "$iface" ]]; then
            resolvectl revert "$iface" 2>/dev/null || true
            # Force NetworkManager to re-apply connection settings to re-push DHCP DNS
            if command -v nmcli &>/dev/null; then
                nmcli device reapply "$iface" 2>/dev/null || true
            fi
            log_success "DNS on $iface reverted to DHCP defaults."
        fi
    else
        log_warn "No automated DNS revert available. Check /etc/resolv.conf manually."
    fi
}
