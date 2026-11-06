#!/usr/bin/env bash
set -Eeuo pipefail
set +x

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "Run this installer as root on a Proxmox VE node."
command -v curl >/dev/null || fail "curl is required."
command -v tar >/dev/null || fail "tar is required."

repo_archive="https://github.com/SourceGrid-core/tconnectsync-proxmox/archive/refs/heads/main.tar.gz"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tconnectsync-install.XXXXXX")"
cleanup() {
    rm -rf -- "${temp_dir}"
}
trap cleanup EXIT

archive="${temp_dir}/source.tar.gz"
echo "Downloading the tconnectsync Proxmox installer..."
curl --fail --silent --show-error --location --retry 3 \
    "${repo_archive}" --output "${archive}"
tar -xzf "${archive}" -C "${temp_dir}"

installer="${temp_dir}/tconnectsync-proxmox-main/scripts/provision-proxmox.sh"
[[ -f "${installer}" ]] || fail "The downloaded package does not contain the Proxmox installer."

if bash "${installer}" "$@"; then
    exit 0
else
    status="$?"
    exit "${status}"
fi
