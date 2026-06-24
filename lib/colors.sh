#!/usr/bin/env bash
# ============================================================================
# netboost/lib/colors.sh
# Terminal output utilities: colors, logging, and formatting.
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${BOLD}${BLUE}=== $1 ===${NC}"
    echo ""
}

print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${DIM}%-28s${NC} %s\n" "$key" "$value"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This command requires root privileges. Run with: sudo netboost <command>"
        exit 1
    fi
}
