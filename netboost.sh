#!/usr/bin/env bash
# ============================================================================
# netboost - Client-side network optimization toolkit for Linux
#
# Optimizes Wi-Fi performance on shared networks by tuning the local
# device's network stack, traffic prioritization, and DNS resolution.
#
# Usage: sudo netboost <command> [options]
#
# Copyright (c) 2026 kikiexe
# ============================================================================

set -euo pipefail

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Load modules
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/wifi.sh"
source "${LIB_DIR}/tcp.sh"
source "${LIB_DIR}/dns.sh"
source "${LIB_DIR}/qos.sh"
source "${LIB_DIR}/monitor.sh"

readonly VERSION="1.0.0"

show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'
             _   _                     _
 _ __   ___| |_| |__   ___   ___  ___| |_
| '_ \ / _ \ __| '_ \ / _ \ / _ \/ __| __|
| | | |  __/ |_| |_) | (_) | (_) \__ \ |_
|_| |_|\___|\__|_.__/ \___/ \___/|___/\__|

BANNER
    echo -e "${NC}${DIM}  Client-side network optimizer v${VERSION}${NC}"
    echo ""
}

show_usage() {
    show_banner
    echo -e "${BOLD}USAGE${NC}"
    echo "  sudo netboost <command> [options]"
    echo ""
    echo -e "${BOLD}COMMANDS${NC}"
    echo "  optimize     Apply all optimizations (Wi-Fi, TCP, DNS, QoS)"
    echo "  status       Show current network status and optimization state"
    echo "  monitor      Real-time network quality dashboard"
    echo "  benchmark    Run DNS provider benchmark"
    echo "  reset        Revert all optimizations to system defaults"
    echo "  help         Show this help message"
    echo ""
    echo -e "${BOLD}EXAMPLES${NC}"
    echo "  sudo netboost optimize          # Apply all optimizations"
    echo "  sudo netboost status            # Check what is active"
    echo "  netboost monitor                # Live monitoring (no sudo needed)"
    echo "  netboost benchmark              # Test DNS providers"
    echo "  sudo netboost reset             # Undo everything"
    echo ""
    echo -e "${BOLD}ENVIRONMENT${NC}"
    echo "  NETBOOST_QOS_RATE    QoS bandwidth limit in kbit/s (default: 15000)"
    echo ""
    echo -e "${BOLD}NOTES${NC}"
    echo "  This tool optimizes your device's network stack only."
    echo "  It does not modify router settings or affect other devices."
    echo "  Optimizations are NOT persistent across reboots."
    echo ""
}

cmd_optimize() {
    require_root
    show_banner
    log_info "Applying all optimizations..."

    optimize_wifi
    optimize_tcp
    optimize_dns
    setup_qos

    log_header "Optimization Complete"
    log_success "All optimizations applied successfully."
    log_info "Run ${BOLD}netboost status${NC} to verify."
    log_info "Run ${BOLD}netboost monitor${NC} to observe the effect in real-time."
    log_info "Run ${BOLD}sudo netboost reset${NC} to revert all changes."
}

cmd_status() {
    show_banner
    log_info "Current network optimization state:"

    get_wifi_status
    get_tcp_status
    get_dns_status
    get_qos_status

    # Quick latency check
    log_header "Quick Latency Check"
    local gw
    gw=$(ip route | grep default | awk '{print $3}' | head -n 1)
    if [[ -n "$gw" ]]; then
        local gw_ping
        gw_ping=$(ping -c 3 -W 2 "$gw" 2>/dev/null | tail -n 1)
        print_kv "Gateway ($gw)" "$gw_ping"
    fi

    local ext_ping
    ext_ping=$(ping -c 3 -W 2 8.8.8.8 2>/dev/null | tail -n 1)
    print_kv "Internet (8.8.8.8)" "$ext_ping"
}

cmd_monitor() {
    show_banner
    local interval="${1:-3}"
    monitor_network "$interval"
}

cmd_benchmark() {
    show_banner
    benchmark_dns_providers
}

cmd_reset() {
    require_root
    show_banner
    log_info "Reverting all optimizations..."

    reset_wifi
    reset_tcp
    reset_dns
    reset_qos

    log_header "Reset Complete"
    log_success "All optimizations reverted to system defaults."
}

# --- Entry point ---

main() {
    local command="${1:-help}"
    shift 2>/dev/null || true

    case "$command" in
        optimize)   cmd_optimize ;;
        status)     cmd_status ;;
        monitor)    cmd_monitor "$@" ;;
        benchmark)  cmd_benchmark ;;
        reset)      cmd_reset ;;
        help|--help|-h)
                    show_usage ;;
        version|--version|-v)
                    echo "netboost v${VERSION}" ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
