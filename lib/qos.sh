#!/usr/bin/env bash
# ============================================================================
# netboost/lib/qos.sh
# Local QoS (Quality of Service) using Linux traffic control (tc).
#
# Architecture:
#   Uses HTB (Hierarchical Token Bucket) as the root qdisc with 3 classes:
#
#   1:10  Interactive  (prio 0)  50% guaranteed, can burst to 100%
#         DNS, SSH, TCP ACKs, ICMP
#   1:20  Normal       (prio 1)  30% guaranteed, can burst to 100%
#         HTTP, HTTPS, general web traffic
#   1:30  Bulk         (prio 2)  20% guaranteed, can burst to 100%
#         Everything else (large downloads, updates, torrents)
#
#   Each class uses fq_codel as the leaf qdisc to minimize bufferbloat.
#
# Why this helps on shared Wi-Fi:
#   This only controls OUTGOING traffic from your device. However, by
#   ensuring TCP ACK packets are sent promptly (class 1:10), the TCP
#   feedback loop stays responsive. This means:
#   - Incoming downloads ramp up faster (ACKs are not delayed)
#   - Interactive traffic (browsing, SSH) stays snappy even during
#     background downloads
#   - Bufferbloat on the upload side is eliminated by fq_codel
# ============================================================================

# Upstream bandwidth estimate in kbit/s.
# Set conservatively: 80% of actual upload speed works best for HTB.
# Can be overridden via environment variable.
readonly QOS_RATE_KBIT="${NETBOOST_QOS_RATE:-15000}"

setup_qos() {
    require_root

    local iface="$WIFI_INTERFACE"
    if [[ -z "$iface" ]]; then
        detect_wifi_interface
        iface="$WIFI_INTERFACE"
    fi

    if [[ -z "$iface" ]]; then
        log_error "No Wi-Fi interface found for QoS."
        return 1
    fi

    log_header "Local Traffic Prioritization (QoS)"
    log_info "Configuring HTB on $iface (rate: ${QOS_RATE_KBIT} kbit/s)"

    # Disable exit-on-error locally: tc commands can fail individually
    # without invalidating the overall setup.
    set +e

    # Remove any existing rules cleanly
    tc qdisc del dev "$iface" root 2>/dev/null

    # Root qdisc: HTB, unclassified traffic defaults to bulk (1:30)
    if ! tc qdisc add dev "$iface" root handle 1: htb default 30 2>/dev/null; then
        log_error "Failed to create root HTB qdisc. Is 'tc' available?"
        set -e
        return 1
    fi

    # Root class: total bandwidth ceiling
    tc class add dev "$iface" parent 1: classid 1:1 htb \
        rate "${QOS_RATE_KBIT}kbit" \
        ceil "${QOS_RATE_KBIT}kbit" 2>/dev/null

    # Class 1:10 - Interactive (50% guaranteed)
    tc class add dev "$iface" parent 1:1 classid 1:10 htb \
        rate "$(( QOS_RATE_KBIT / 2 ))kbit" \
        ceil "${QOS_RATE_KBIT}kbit" \
        prio 0 2>/dev/null

    # Class 1:20 - Normal (30% guaranteed)
    tc class add dev "$iface" parent 1:1 classid 1:20 htb \
        rate "$(( QOS_RATE_KBIT * 3 / 10 ))kbit" \
        ceil "${QOS_RATE_KBIT}kbit" \
        prio 1 2>/dev/null

    # Class 1:30 - Bulk (20% guaranteed)
    tc class add dev "$iface" parent 1:1 classid 1:30 htb \
        rate "$(( QOS_RATE_KBIT / 5 ))kbit" \
        ceil "${QOS_RATE_KBIT}kbit" \
        prio 2 2>/dev/null

    # Leaf qdiscs: fq_codel on each class for anti-bufferbloat
    tc qdisc add dev "$iface" parent 1:10 handle 10: fq_codel 2>/dev/null
    tc qdisc add dev "$iface" parent 1:20 handle 20: fq_codel 2>/dev/null
    tc qdisc add dev "$iface" parent 1:30 handle 30: fq_codel 2>/dev/null

    # --- Traffic classification filters ---

    # DNS (UDP/TCP port 53) -> Interactive
    tc filter add dev "$iface" parent 1: protocol ip prio 1 \
        u32 match ip dport 53 0xffff flowid 1:10 2>/dev/null
    tc filter add dev "$iface" parent 1: protocol ip prio 1 \
        u32 match ip sport 53 0xffff flowid 1:10 2>/dev/null

    # SSH (port 22) -> Interactive
    tc filter add dev "$iface" parent 1: protocol ip prio 1 \
        u32 match ip dport 22 0xffff flowid 1:10 2>/dev/null

    # ICMP (ping) -> Interactive
    tc filter add dev "$iface" parent 1: protocol ip prio 1 \
        u32 match ip protocol 1 0xff flowid 1:10 2>/dev/null

    # TCP ACKs (small TCP packets, <= 128 bytes) -> Interactive
    # This is the most impactful rule: fast ACKs keep the download pipeline full.
    tc filter add dev "$iface" parent 1: protocol ip prio 2 \
        u32 match ip protocol 6 0xff \
        match u8 0x10 0x10 at nexthdr+13 \
        match u16 0x0000 0xff80 at 2 \
        flowid 1:10 2>/dev/null

    # HTTP (port 80) -> Normal
    tc filter add dev "$iface" parent 1: protocol ip prio 3 \
        u32 match ip dport 80 0xffff flowid 1:20 2>/dev/null

    # HTTPS (port 443) -> Normal
    tc filter add dev "$iface" parent 1: protocol ip prio 3 \
        u32 match ip dport 443 0xffff flowid 1:20 2>/dev/null

    # Re-enable exit-on-error
    set -e

    # Verify the setup worked
    if tc qdisc show dev "$iface" 2>/dev/null | grep -q "htb"; then
        log_success "QoS rules applied on $iface."
    else
        log_error "QoS setup failed. HTB qdisc not found on $iface."
        return 1
    fi
    echo ""
    print_kv "Interactive (1:10)" "DNS, SSH, ICMP, TCP ACKs"
    print_kv "Normal (1:20)"     "HTTP, HTTPS"
    print_kv "Bulk (1:30)"       "Everything else"
    print_kv "Anti-bufferbloat"  "fq_codel on all classes"
}

get_qos_status() {
    log_header "QoS Status"

    local iface="$WIFI_INTERFACE"
    if [[ -z "$iface" ]]; then
        detect_wifi_interface
        iface="$WIFI_INTERFACE"
    fi

    if [[ -z "$iface" ]]; then
        log_error "No Wi-Fi interface found."
        return 1
    fi

    local root_qdisc
    root_qdisc=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1)

    if echo "$root_qdisc" | grep -q "htb"; then
        log_success "QoS is ${GREEN}ACTIVE${NC} on $iface"
        echo ""

        echo -e "  ${DIM}Class statistics:${NC}"
        tc -s class show dev "$iface" 2>/dev/null | while IFS= read -r line; do
            echo "    $line"
        done
    else
        log_warn "QoS is ${YELLOW}INACTIVE${NC} on $iface."
        print_kv "Current root qdisc" "$root_qdisc"
    fi
}

reset_qos() {
    require_root

    local iface="$WIFI_INTERFACE"
    if [[ -z "$iface" ]]; then
        detect_wifi_interface
        iface="$WIFI_INTERFACE"
    fi

    if [[ -n "$iface" ]]; then
        tc qdisc del dev "$iface" root 2>/dev/null
        log_success "QoS rules removed from $iface. Default qdisc restored."
    fi
}
