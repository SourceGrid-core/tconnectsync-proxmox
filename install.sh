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
command -v sha256sum >/dev/null || fail "sha256sum is required to verify downloaded installer files."

repo_commit="de8cd4b4fdc951616b8a51b38f832a4e73ab36b5"
archive_sha256="6e3105fe694ff8f293137afea7c56843b7426b85c9261d0ad9ce3ecbee1d08e1"
repo_base="https://raw.githubusercontent.com/SourceGrid-core/tconnectsync-proxmox/${repo_commit}"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tconnectsync-install.XXXXXX")"
cleanup() {
    rm -rf -- "${temp_dir}"
}
trap cleanup EXIT

archive="${temp_dir}/source.tar.gz"
echo "Downloading the tconnectsync Proxmox installer..."
if curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 --max-time 120 \
    "https://codeload.github.com/SourceGrid-core/tconnectsync-proxmox/tar.gz/${repo_commit}" \
    --output "${archive}" 2>"${temp_dir}/curl-error"; then
    printf '%s  %s\n' "${archive_sha256}" "${archive}" | sha256sum --check --status ||
        fail "The downloaded package failed its pinned SHA-256 integrity check; refusing to run it."
    tar -xzf "${archive}" -C "${temp_dir}"
else
    echo "The codeload archive endpoint was unavailable; retrying individual files from raw.githubusercontent.com."
    rm -f -- "${archive}"
    fallback="${temp_dir}/raw-package"
    mkdir -p "${fallback}/config" "${fallback}/scripts" "${fallback}/systemd"

    fetch_raw_file() {
        local path="$1" expected_sha256="$2" destination="${fallback}/$1"
        mkdir -p "$(dirname -- "${destination}")"
        curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 --max-time 60 \
            "${repo_base}/${path}" --output "${destination}" ||
            fail "Unable to download pinned package file: ${path}"
        printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status ||
            fail "Pinned SHA-256 integrity check failed for ${path}; refusing to run it."
    }

    fetch_raw_file README.md 7d45a08f3fde7b3673294f67af1a25adf3cd9d876384fe9deb1e6e7d3ca53aa1
    fetch_raw_file config/tconnectsync.env.example f069a2aac22ff68947be91d822fa5813938a3893eabd9e40dd241d53f107d713
    fetch_raw_file scripts/check-config.py 82ac718e4b821de94a128fedf8160dd933b41e057d13b461077df4eaefbb279e
    fetch_raw_file scripts/install-debian.sh 1edcaeb91ef9a9afad160fb1a4ee59e4f941773d8ba4800ef77e9d1d11d08ed9
    fetch_raw_file scripts/provision-proxmox.sh f4d47267198835844e718ff9f6a92544e5029055c4b27b202f530a551dc2a1b0
    fetch_raw_file scripts/update-container.sh d1ab10408de363537aa863cad4af7d65c1d3b60fe980ddc376fb9a1058489feb
    fetch_raw_file scripts/update.sh 68d134bf71ed3251be40d849dad4372e9bd4124c40be260cf3a594dc5d373093
    fetch_raw_file systemd/tconnectsync.service b76e138f66b5217d663b27ca236511eeef2eba29ba04e29c063e313773e05ec9
    mv "${fallback}" "${temp_dir}/tconnectsync-proxmox-${repo_commit}"
fi

installer="${temp_dir}/tconnectsync-proxmox-${repo_commit}/scripts/provision-proxmox.sh"
[[ -f "${installer}" ]] || fail "The downloaded package does not contain the Proxmox installer."

if bash "${installer}" "$@"; then
    exit 0
else
    status="$?"
    exit "${status}"
fi
