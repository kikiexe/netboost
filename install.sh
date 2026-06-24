#!/usr/bin/env bash
# ============================================================================
# netboost installer
# Copies toolkit to a secure system path and creates a system-wide symlink.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/netboost"
SECURE_LIB_DIR="/usr/local/share/netboost"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash install.sh"
    exit 1
fi

mkdir -p "$SECURE_LIB_DIR"
chown root:root "$SECURE_LIB_DIR"
chmod 755 "$SECURE_LIB_DIR"

# Clean any existing installation files to prevent mixups
rm -rf "$SECURE_LIB_DIR"/*

# Copy workspace files securely
cp -r "${SCRIPT_DIR}/"* "$SECURE_LIB_DIR/"
chown -R root:root "$SECURE_LIB_DIR"
chmod -R u=rwX,go=rX "$SECURE_LIB_DIR"
chmod +x "$SECURE_LIB_DIR/netboost.sh"
chmod +x "$SECURE_LIB_DIR/install.sh"

ln -sf "$SECURE_LIB_DIR/netboost.sh" "$INSTALL_PATH"

echo "netboost installed securely to $INSTALL_PATH"
echo "Usage: sudo netboost optimize"
