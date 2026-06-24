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

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

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
DRY_RUN=0
FORCE_OPTIMIZE=0


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
    if [[ "$DRY_RUN" -eq 1 ]]; then
        show_banner
        log_info "Running in DRY RUN mode (simulating actions)..."
    else
        require_root
        show_banner

        if [[ "$FORCE_OPTIMIZE" -eq 0 ]]; then
            echo -e "${BOLD}Optimization Summary:${NC}"
            echo -e "  * ${BOLD}Wi-Fi:${NC} Disable power saving mode to reduce latency spikes."
            echo -e "  * ${BOLD}TCP/Kernel:${NC} Tune kernel parameters (BBR congestion control, TCP windows, timeouts)."
            echo -e "  * ${BOLD}DNS:${NC} Apply low-latency public resolvers (1.1.1.1, 1.0.0.1)."
            echo -e "  * ${BOLD}QoS:${NC} Prioritize interactive traffic (DNS, SSH, ICMP, TCP ACKs)."
            echo ""
            read -r -p "Are you sure you want to apply these system-wide changes? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_warn "Optimization aborted by user."
                exit 0
            fi
            echo ""
        fi

        log_info "Applying all optimizations..."
    fi

    optimize_wifi
    optimize_tcp
    optimize_dns
    setup_qos

    log_header "Optimization Complete"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "All dry-run optimizations simulated successfully."
    else
        log_success "All optimizations applied successfully."
        log_info "Run ${BOLD}netboost status${NC} to verify."
        log_info "Run ${BOLD}netboost monitor${NC} to observe the effect in real-time."
        log_info "Run ${BOLD}sudo netboost reset${NC} to revert all changes."
    fi
}

cmd_status() {
    show_banner
    log_info "Current network optimization state:"

    get_wifi_status || true
    get_tcp_status || true
    get_dns_status || true
    get_qos_status || true

    # Quick latency check
    log_header "Quick Latency Check"
    local gw
    gw=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n 1 || true)
    if [[ -n "$gw" ]]; then
        local gw_ping
        gw_ping=$(ping -c 3 -W 2 "$gw" 2>/dev/null | tail -n 1 || true)
        print_kv "Gateway ($gw)" "${gw_ping:-TIMEOUT}"
    fi

    local ext_ping
    ext_ping=$(ping -c 3 -W 2 8.8.8.8 2>/dev/null | tail -n 1 || true)
    print_kv "Internet (8.8.8.8)" "${ext_ping:-TIMEOUT}"
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

    if [[ "$command" =~ ^-{2}help$ ]]; then
        command="help"
    elif [[ "$command" =~ ^-{2}version$ ]]; then
        command="version"
    fi

    DRY_RUN=0
    FORCE_OPTIMIZE=0
    local pass_args=()
    for arg in "$@"; do
        if [[ "$arg" =~ ^-{2}dry-run$ ]] || [[ "$arg" == "-d" ]]; then
            DRY_RUN=1
        elif [[ "$arg" =~ ^-{2}yes$ ]] || [[ "$arg" =~ ^-{2}force$ ]] || [[ "$arg" == "-y" ]] || [[ "$arg" == "-f" ]]; then
            FORCE_OPTIMIZE=1
        else
            pass_args+=("$arg")
        fi
    done

    case "$command" in
        optimize)   cmd_optimize ;;
        status)     cmd_status ;;
        monitor)    cmd_monitor "${pass_args[@]}" ;;
        benchmark)  cmd_benchmark ;;
        reset)      cmd_reset ;;
        help|-h)
                    show_usage ;;
        version|-v)
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
