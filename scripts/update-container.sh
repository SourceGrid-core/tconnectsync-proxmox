#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this updater on a Proxmox VE node as root." >&2
    exit 1
fi
command -v pct >/dev/null || {
    echo "pct is unavailable; run this on a Proxmox VE node." >&2
    exit 1
}

if [[ "$#" -ne 1 || ! "$1" =~ ^[0-9]+$ || "$1" -lt 100 ]]; then
    echo "Usage: $0 <CTID>" >&2
    exit 2
fi
ctid="$1"
[[ -e "/etc/pve/lxc/${ctid}.conf" ]] || {
    echo "Container ${ctid} does not exist on this node." >&2
    exit 1
}
pct status "${ctid}" | grep -q 'status: running' || {
    echo "Container ${ctid} must be running." >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
temp_dir="$(mktemp -d)"
bundle="${temp_dir}/package.tar.gz"
cleanup() {
    rm -f -- "${bundle}"
    rmdir -- "${temp_dir}"
}
trap cleanup EXIT

tar -czf "${bundle}" -C "${repo_dir}" README.md config scripts systemd
pct push "${ctid}" "${bundle}" /tmp/tconnectsync-package.tar.gz
pct exec "${ctid}" -- tar -xzf /tmp/tconnectsync-package.tar.gz -C /opt/tconnectsync-deployment
pct exec "${ctid}" -- rm -f /tmp/tconnectsync-package.tar.gz
pct exec "${ctid}" -- bash /opt/tconnectsync-deployment/scripts/install-debian.sh
echo "Updated deployment files and reinstalled the service in CT ${ctid}; existing configuration was preserved."
