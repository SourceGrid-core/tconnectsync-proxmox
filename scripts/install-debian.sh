#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root (for example: sudo $0)." >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify the operating system; Debian 12 or newer is required." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_ID%%.*}" -lt 12 ]]; then
    echo "Debian 12 or newer is required; found ${PRETTY_NAME:-unknown}." >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
service_name="tconnectsync"
service_group="${service_name}"
service_user="${service_name}"
state_dir="/var/lib/${service_name}"
config_dir="/etc/${service_name}"
venv_dir="/opt/${service_name}/venv"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    python3-venv \
    tzdata

if ! getent group "${service_group}" >/dev/null; then
    groupadd --system "${service_group}"
fi
if ! id "${service_user}" >/dev/null 2>&1; then
    useradd --system --gid "${service_group}" --home-dir "${state_dir}" \
        --create-home --shell /usr/sbin/nologin "${service_user}"
fi

install -d -o "${service_user}" -g "${service_group}" -m 0700 \
    "${state_dir}" "${state_dir}/.config" "${state_dir}/.config/${service_name}"
install -d -o root -g "${service_group}" -m 0750 "${config_dir}"

if [[ ! -e "${config_dir}/${service_name}.env" ]]; then
    install -o root -g "${service_group}" -m 0640 \
        "${repo_dir}/config/${service_name}.env.example" \
        "${config_dir}/${service_name}.env"
else
    chown root:"${service_group}" "${config_dir}/${service_name}.env"
    chmod 0640 "${config_dir}/${service_name}.env"
fi

install -d -o root -g root -m 0755 "/opt/${service_name}"
if [[ ! -x "${venv_dir}/bin/python" ]]; then
    python3 -m venv "${venv_dir}"
fi
"${venv_dir}/bin/python" -m pip install --upgrade tconnectsync

install -d -o root -g root -m 0755 "/usr/local/libexec/${service_name}"
install -o root -g root -m 0644 "${repo_dir}/scripts/check-config.py" \
    "/usr/local/libexec/${service_name}/check-config.py"
install -o root -g root -m 0644 "${repo_dir}/systemd/${service_name}.service" \
    "/etc/systemd/system/${service_name}.service"

systemctl daemon-reload
systemctl enable "${service_name}.service"

echo
echo "Installed. Edit ${config_dir}/${service_name}.env, then run:"
echo "  systemctl start ${service_name}"
echo "  systemctl status ${service_name} --no-pager"
