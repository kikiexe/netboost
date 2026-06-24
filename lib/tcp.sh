#!/usr/bin/env bash
# ============================================================================
# netboost/lib/tcp.sh
# TCP kernel parameter tuning for congested and lossy Wi-Fi networks.
#
# Key optimizations:
#   - BBR congestion control: handles packet loss without halving throughput
#     (unlike CUBIC). Critical for Wi-Fi where "loss" is often interference,
#     not congestion.
#   - TCP Fast Open: saves 1 RTT on connection setup (significant when
#     base latency is already high).
#   - Disable slow start after idle: prevents throughput from dropping to
#     zero on connections that pause briefly (e.g. browsing tabs).
#   - MTU probing: discovers the optimal packet size to avoid fragmentation.
#   - Tuned buffer sizes: sized for realistic Wi-Fi throughput, not
#     datacenter links.
#   - Aggressive keepalive: detects dead connections faster so sockets
#     are freed sooner.
# ============================================================================

readonly SYSCTL_BACKUP_FILE="/tmp/netboost_sysctl_backup.conf"

backup_sysctl_params() {
    local params=(
        "net.core.default_qdisc"
        "net.ipv4.tcp_congestion_control"
        "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_slow_start_after_idle"
        "net.ipv4.tcp_mtu_probing"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.tcp_keepalive_intvl"
        "net.ipv4.tcp_keepalive_probes"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_notsent_lowat"
    )

    : > "$SYSCTL_BACKUP_FILE"
    for param in "${params[@]}"; do
        local value
        value=$(sysctl -n "$param" 2>/dev/null)
        if [[ -n "$value" ]]; then
            echo "$param = $value" >> "$SYSCTL_BACKUP_FILE"
        fi
    done
    log_info "Original TCP parameters saved to $SYSCTL_BACKUP_FILE"
}

apply_sysctl() {
    local param="$1"
    local value="$2"
    local description="$3"

    if sysctl -w "${param}=${value}" >/dev/null 2>&1; then
        log_success "$description"
    else
        log_error "Failed: $description"
    fi
}

optimize_tcp() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_header "TCP Stack Optimization [DRY RUN]"
        log_info "Would back up current TCP settings to $SYSCTL_BACKUP_FILE"
        log_info "Would enable fq qdisc and BBR congestion control if available"
        log_info "Would tune TCP windows, keepalive, and timeouts"
        return 0
    fi

    require_root

    log_header "TCP Stack Optimization"

    backup_sysctl_params

    # Load BBR kernel module if not already loaded
    modprobe tcp_bbr 2>/dev/null || true

    # BBR congestion control with fair queuing scheduler
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        apply_sysctl "net.core.default_qdisc" "fq" \
            "Qdisc set to fair queuing (fq)."
        apply_sysctl "net.ipv4.tcp_congestion_control" "bbr" \
            "Congestion control set to BBR."
    else
        log_warn "BBR not available in this kernel. Keeping current congestion control."
    fi

    apply_sysctl "net.ipv4.tcp_fastopen" "3" \
        "TCP Fast Open enabled (client + server)."

    apply_sysctl "net.ipv4.tcp_slow_start_after_idle" "0" \
        "Slow start after idle disabled."

    apply_sysctl "net.ipv4.tcp_mtu_probing" "1" \
        "MTU probing enabled."

    # Buffer sizes: min=4KB / default=256KB / max=16MB (read), 16MB (write)
    # Sized for claiming maximum bandwidth on high-speed networks.
    apply_sysctl "net.ipv4.tcp_rmem" "4096 262144 16777216" \
        "TCP read buffer optimized (4K/256K/16M)."
    apply_sysctl "net.ipv4.tcp_wmem" "4096 131072 16777216" \
        "TCP write buffer optimized (4K/128K/16M)."
    apply_sysctl "net.core.rmem_max" "16777216" \
        "Max socket read buffer set to 16MB."
    apply_sysctl "net.core.wmem_max" "16777216" \
        "Max socket write buffer set to 16MB."

    # Limit unsent queued data to prevent socket bufferbloat and make BBR pacing highly responsive.
    apply_sysctl "net.ipv4.tcp_notsent_lowat" "16384" \
        "TCP notsent lowat optimized to 16KB."

    # Keepalive: check after 2 minutes, retry every 10s, give up after 6 retries
    apply_sysctl "net.ipv4.tcp_keepalive_time" "120" \
        "Keepalive probe start: 120s (was 7200s)."
    apply_sysctl "net.ipv4.tcp_keepalive_intvl" "10" \
        "Keepalive probe interval: 10s."
    apply_sysctl "net.ipv4.tcp_keepalive_probes" "6" \
        "Keepalive max probes: 6."

    apply_sysctl "net.ipv4.tcp_fin_timeout" "15" \
        "FIN timeout reduced to 15s (frees sockets faster)."
}

get_tcp_status() {
    log_header "TCP Stack Status"

    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local cc_color="$NC"
    if [[ "$cc" == "bbr" ]]; then
        cc_color="$GREEN"
    fi

    echo -e "  ${DIM}$(printf '%-28s' "Congestion Control")${NC} ${cc_color}${cc}${NC}"
    print_kv "Default Qdisc"            "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    print_kv "TCP Fast Open"            "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"
    print_kv "Slow Start After Idle"    "$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)"
    print_kv "MTU Probing"              "$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null)"
    print_kv "Keepalive Time"           "$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null)s"
    print_kv "FIN Timeout"              "$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null)s"
    print_kv "Read Buffer (min/def/max)" "$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
    print_kv "Write Buffer (min/def/max)" "$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
    print_kv "TCP Notsent Lowat"        "$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)"
}

reset_tcp() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_header "TCP Stack Reset [DRY RUN]"
        log_info "Would restore TCP settings from backup file ($SYSCTL_BACKUP_FILE) if it exists, or apply default values"
        return 0
    fi

    require_root

    if [[ -f "$SYSCTL_BACKUP_FILE" ]]; then
        sysctl -p "$SYSCTL_BACKUP_FILE" >/dev/null 2>&1
        log_success "TCP parameters restored from backup."
        rm -f "$SYSCTL_BACKUP_FILE"
    else
        log_warn "No backup found. Applying standard defaults."
        apply_sysctl "net.core.default_qdisc" "fq_codel"           "Qdisc reset to fq_codel."
        apply_sysctl "net.ipv4.tcp_congestion_control" "cubic"     "Congestion control reset to CUBIC."
        apply_sysctl "net.ipv4.tcp_fastopen" "1"                   "TCP Fast Open reset."
        apply_sysctl "net.ipv4.tcp_slow_start_after_idle" "1"      "Slow start after idle re-enabled."
        apply_sysctl "net.ipv4.tcp_mtu_probing" "0"                "MTU probing disabled."
        apply_sysctl "net.ipv4.tcp_keepalive_time" "7200"          "Keepalive time reset to 7200s."
        apply_sysctl "net.ipv4.tcp_keepalive_intvl" "75"           "Keepalive interval reset to 75s."
        apply_sysctl "net.ipv4.tcp_keepalive_probes" "9"           "Keepalive probes reset to 9."
        apply_sysctl "net.ipv4.tcp_fin_timeout" "60"               "FIN timeout reset to 60s."
        apply_sysctl "net.ipv4.tcp_notsent_lowat" "4294967295"    "TCP notsent lowat reset to unlimited."
    fi
}
