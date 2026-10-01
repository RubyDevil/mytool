#!/bin/bash
# Run by mytool as root before removing or updating fan-speed: uninstall.sh <installed script path>

set -euo pipefail

rm -f -- "${MYTOOL_SUDOERS_DIR:-/etc/sudoers.d}/mytool-fan-speed"
