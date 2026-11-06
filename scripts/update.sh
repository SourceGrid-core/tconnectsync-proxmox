#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this updater as root (for example: sudo $0)." >&2
    exit 1
fi

venv_python="/opt/tconnectsync/venv/bin/python"
if [[ ! -x "${venv_python}" ]]; then
    echo "tconnectsync is not installed; run scripts/install-debian.sh first." >&2
    exit 1
fi
if ! systemctl cat tconnectsync.service >/dev/null 2>&1; then
    echo "The tconnectsync systemd service is not installed." >&2
    exit 1
fi

"${venv_python}" -m pip install --upgrade tconnectsync
systemctl restart tconnectsync.service
systemctl is-active --quiet tconnectsync.service || {
    echo "The service did not remain active after the update. Inspect: journalctl -u tconnectsync." >&2
    exit 1
}
echo "Updated tconnectsync and restarted the service."
