#!/usr/bin/env bash
set -Eeuo pipefail
set +x

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "Run on a Proxmox VE node as root."
command -v pct >/dev/null || fail "pct is unavailable; run this on a Proxmox VE node."
command -v pvesh >/dev/null || fail "pvesh is unavailable; run this on a Proxmox VE node."

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"

read_value() {
    local prompt="$1" default="$2" value
    if [[ -n "${default}" ]]; then
        read -r -p "${prompt} [${default}]: " value
        printf '%s' "${value:-$default}"
    else
        read -r -p "${prompt}: " value
        printf '%s' "${value}"
    fi
}

read_secret() {
    local prompt="$1" value
    read -r -s -p "${prompt}: " value
    printf '\n' >&2
    printf '%s' "${value}"
}

template="$(read_value 'Debian 12+ template (storage:vztmpl/file.tar.zst)' '')"
[[ "${template}" =~ ^[A-Za-z0-9._-]+:vztmpl/debian-1[2-9]-standard_[A-Za-z0-9._-]+\.tar\.(zst|gz|xz)$ ]] ||
    fail "Use a Debian 12 or newer standard template ID, such as local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst."
storage="$(read_value 'Root filesystem storage ID' 'local-lvm')"
[[ "${storage}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Invalid storage ID."
bridge="$(read_value 'Proxmox network bridge' 'vmbr0')"
[[ "${bridge}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Invalid bridge name."
net_config="$(read_value 'Container net0 configuration' "name=eth0,bridge=${bridge},ip=dhcp")"
[[ "${net_config}" != *$'\n'* ]] || fail "Network configuration must be a single line."
ssh_key="$(read_value 'Path to an SSH public key on this Proxmox node' '')"
[[ -r "${ssh_key}" ]] || fail "The SSH public key file is not readable."
grep -Eq '^(ssh-|ecdsa-|sk-ssh-)[^[:space:]]+[[:space:]]' "${ssh_key}" ||
    fail "The key file does not look like an OpenSSH public key."

ctid="$(pvesh get /cluster/nextid)"
[[ "${ctid}" =~ ^[0-9]+$ && "${ctid}" -ge 100 ]] || fail "Proxmox returned an invalid next container ID."
[[ ! -e "/etc/pve/lxc/${ctid}.conf" ]] || fail "Container ${ctid} already exists; refusing to modify it."

echo "Provisioning new Debian LXC ${ctid} from ${template}."
echo "This script will not overwrite or delete an existing container."
echo "After configuration, it will start tconnectsync and begin syncing to the Nightscout URL you provide."
read -r -p "Continue? [y/N]: " confirmation
[[ "${confirmation}" == [yY] ]] || fail "Cancelled."

tconnect_email="$(read_value 'TCONNECT_EMAIL' '')"
tconnect_password="$(read_secret 'TCONNECT_PASSWORD')"
tconnect_region="$(read_value 'TCONNECT_REGION (US or EU)' 'US')"
ns_url="$(read_value 'NS_URL' '')"
ns_secret="$(read_secret 'NS_SECRET')"
timezone_name="$(read_value 'TIMEZONE_NAME (pump timezone)' 'America/New_York')"
pump_serial="$(read_value 'PUMP_SERIAL_NUMBER (optional; press Enter to skip)' '')"

for pair in \
    "TCONNECT_EMAIL:${tconnect_email}" \
    "TCONNECT_PASSWORD:${tconnect_password}" \
    "NS_URL:${ns_url}" \
    "NS_SECRET:${ns_secret}" \
    "TIMEZONE_NAME:${timezone_name}"; do
    [[ -n "${pair#*:}" ]] || fail "${pair%%:*} is required."
done
[[ "${tconnect_region}" == "US" || "${tconnect_region}" == "EU" ]] ||
    fail "TCONNECT_REGION must be US or EU."
[[ "${ns_url}" =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]] ||
    fail "NS_URL must be an absolute HTTP(S) URL."
[[ "${timezone_name}" != /* && "${timezone_name}" != *..* &&
    "${timezone_name}" =~ ^[A-Za-z0-9_+./-]+$ &&
    -f "/usr/share/zoneinfo/${timezone_name}" ]] ||
    fail "TIMEZONE_NAME must be a valid timezone database name."
[[ -z "${pump_serial}" || "${pump_serial}" =~ ^[0-9]+$ ]] ||
    fail "PUMP_SERIAL_NUMBER must contain only digits when set."

temp_dir="$(mktemp -d)"
config_file="${temp_dir}/tconnectsync.env"
bundle="${temp_dir}/package.tar.gz"
cleanup() {
    rm -f -- "${config_file}" "${bundle}"
    rmdir -- "${temp_dir}"
}
trap cleanup EXIT

write_env() {
    local name="$1" value="$2" escaped
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] ||
        fail "${name} must not contain a newline."
    escaped="${value//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s="%s"\n' "${name}" "${escaped}" >>"${config_file}"
}

: >"${config_file}"
write_env TCONNECT_EMAIL "${tconnect_email}"
write_env TCONNECT_PASSWORD "${tconnect_password}"
write_env TCONNECT_REGION "${tconnect_region}"
write_env NS_URL "${ns_url}"
write_env NS_SECRET "${ns_secret}"
write_env TIMEZONE_NAME "${timezone_name}"
if [[ -n "${pump_serial}" ]]; then
    write_env PUMP_SERIAL_NUMBER "${pump_serial}"
fi
chmod 0600 "${config_file}"

tar -czf "${bundle}" -C "${repo_dir}" \
    README.md config scripts systemd

pct create "${ctid}" "${template}" \
    --hostname tconnectsync \
    --ostype debian \
    --unprivileged 1 \
    --cores 1 \
    --memory 1024 \
    --swap 512 \
    --rootfs "${storage}:8" \
    --net0 "${net_config}" \
    --onboot 1 \
    --startup order=3 \
    --ssh-public-keys "${ssh_key}" \
    --description "Tandem tconnectsync to Nightscout"
pct start "${ctid}"

for _ in {1..30}; do
    if pct exec "${ctid}" -- true >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
pct exec "${ctid}" -- true >/dev/null 2>&1 ||
    fail "Container ${ctid} did not become available. It was left intact for inspection."

pct push "${ctid}" "${bundle}" /tmp/tconnectsync-package.tar.gz
pct exec "${ctid}" -- mkdir -p /opt/tconnectsync-deployment
pct exec "${ctid}" -- tar -xzf /tmp/tconnectsync-package.tar.gz -C /opt/tconnectsync-deployment
pct exec "${ctid}" -- rm -f /tmp/tconnectsync-package.tar.gz
pct exec "${ctid}" -- bash /opt/tconnectsync-deployment/scripts/install-debian.sh

pct push "${ctid}" "${config_file}" /etc/tconnectsync/tconnectsync.env
pct exec "${ctid}" -- chown root:tconnectsync /etc/tconnectsync/tconnectsync.env
pct exec "${ctid}" -- chmod 0640 /etc/tconnectsync/tconnectsync.env
pct exec "${ctid}" -- systemctl start tconnectsync.service
sleep 5

echo
echo "Container ${ctid} was created and configured."
echo "Check status: pct exec ${ctid} -- systemctl status tconnectsync --no-pager"
echo "View logs:    pct exec ${ctid} -- journalctl -u tconnectsync -n 100 --no-pager"
if ! pct exec "${ctid}" -- systemctl is-active --quiet tconnectsync.service; then
    echo "The service is not active yet; the container was left intact. Inspect its journal." >&2
    exit 1
fi
