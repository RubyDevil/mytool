#!/bin/bash
# Run by mytool as root after installing fan-speed: install.sh <installed script path>

set -euo pipefail

target="${1-}"
sudoers_file="${MYTOOL_SUDOERS_DIR:-/etc/sudoers.d}/mytool-fan-speed"
groups=()

# The path is written into sudoers, so only accept plain absolute paths.
if [[ ! "$target" =~ ^/[A-Za-z0-9/_-]+$ ]]; then
    echo "Refusing unsafe script path: $target" >&2
    exit 2
fi

if ! command -v ipmitool >/dev/null; then
    apt-get install -y ipmitool
fi

for group in sudo admin wheel; do
    if getent group "$group" >/dev/null; then
        groups+=("$group")
    fi
done
if ((${#groups[@]} == 0)); then
    echo "No sudo, admin, or wheel group exists on this system." >&2
    exit 1
fi

temporary_file=$(mktemp)
trap 'rm -f -- "$temporary_file"' EXIT
{
    echo "# Managed by mytool: lets sudoers run $target without a password."
    for group in "${groups[@]}"; do
        echo "%$group ALL=(root) NOPASSWD: $target"
    done
} >"$temporary_file"

# A broken sudoers file can lock everyone out of sudo, so validate before installing.
visudo -cqf "$temporary_file"
# sudo ignores sudoers.d files containing a dot, so the staged file is never active.
install -D -m 440 -- "$temporary_file" "$sudoers_file.new"
mv -f -- "$sudoers_file.new" "$sudoers_file"
