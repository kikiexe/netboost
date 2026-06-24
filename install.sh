#!/usr/bin/env bash
# ============================================================================
# netboost installer
# Creates a system-wide symlink so 'netboost' works from anywhere.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/netboost"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash install.sh"
    exit 1
fi

chmod +x "${SCRIPT_DIR}/netboost.sh"

ln -sf "${SCRIPT_DIR}/netboost.sh" "$INSTALL_PATH"

echo "netboost installed to $INSTALL_PATH"
echo "Usage: sudo netboost optimize"
