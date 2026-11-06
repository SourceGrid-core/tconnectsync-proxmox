# tconnectsync on Proxmox LXC

This repository packages the upstream [`jwoglom/tconnectsync`](https://github.com/jwoglom/tconnectsync) Python application for a Debian Linux Container (LXC) on Proxmox VE. It installs the published `tconnectsync` package into an isolated Python virtual environment and runs it as a native systemd service. The upstream application is not copied or modified here.

## One-command Proxmox install

The installer runs on a **Proxmox VE node**, not inside a pre-existing LXC. It creates a new, unprivileged Debian 12 LXC, installs the upstream application and systemd service, writes your configuration with restricted permissions, and starts the service. It will never overwrite or delete an existing container.

From a root shell on the Proxmox node, run this single command:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SourceGrid-core/tconnectsync-proxmox/sourcegrid-core-proxmox-lxc-deployment/install.sh)"
```

The repository is public so this raw installer link works without GitHub credentials or a pre-existing clone. The bootstrap downloads the deployment package from a pinned commit using `codeload.github.com`, checks the archive's SHA-256 digest, and then runs the interactive installer. If codeload is unreachable, it fetches the individual files from `raw.githubusercontent.com` and verifies each against a pinned SHA-256 digest. It does not use `github.com` archive URLs, disable TLS verification, or execute unverified downloads. Do not pipe a downloaded script into a shell unless you trust its source; review [`install.sh`](install.sh) and [`scripts/provision-proxmox.sh`](scripts/provision-proxmox.sh) first if desired.

The installer requires a Proxmox VE host shell, root privileges, `curl`, `tar`, and working Proxmox package repositories/internet access. It checks for the Proxmox tools before provisioning.

Before installing:

- Use a Proxmox VE node with working Proxmox package repositories, outbound internet access, and available `pct`, `pvesh`, `pveam`, and `pvesm` commands. Run the workflow from the node shell as root (or with `sudo`).
- Ensure the selected root filesystem storage supports container root disks and has at least 8 GB available. The script lists configured storages and asks separately where to store the template (commonly `local`) and the container disk (commonly `local-lvm`).
- Ensure the node has a network bridge (commonly `vmbr0`) connected to a network with DHCP and outbound DNS/HTTPS. Static IPv4 settings can be entered at the prompt instead.
- Put an OpenSSH public key on the Proxmox node for your administration account. The script installs it as the container's root SSH key; the installer enables OpenSSH with public-key authentication only and does not set a root password.
- Have an SSH public key on the Proxmox node. You do not need to clone this repository; the installer downloads the deployment files itself.

The script refreshes Proxmox's official system-template catalog, selects the latest Debian 12 standard template, and downloads it with `pveam` if it is not already on the selected template storage. It selects the next free CT ID and asks for template storage, root-disk storage, bridge, network configuration, SSH public-key path, and CT resource limits. Review the printed CT ID, selected template, and resources before confirming creation. Defaults are 1 CPU core, 1 GiB RAM, 512 MiB swap, 8 GiB root disk, DHCP, and start-at-boot. For a static IPv4 setup, enter a full `net0` value such as `name=eth0,bridge=vmbr0,ip=192.0.2.20/24,gw=192.0.2.1`.

It then prompts for `TCONNECT_EMAIL`, `TCONNECT_PASSWORD`, `TCONNECT_REGION`, `NS_URL`, `NS_SECRET`, `TIMEZONE_NAME`, and optional `PUMP_SERIAL_NUMBER`. Password and API secret input is hidden. Credentials are written to a mode-`0600` temporary file on the Proxmox node, pushed into the new CT, and installed as `/etc/tconnectsync/tconnectsync.env` (`root:tconnectsync`, mode `0640`). The host-side temporary files are removed on exit; secrets are never supplied as command-line arguments or committed to this repository. Do not enable shell tracing while running the script.

`TCONNECT_REGION` must be `US` or `EU`. `TIMEZONE_NAME` must be a timezone database name matching the pump's timezone. Leave `PUMP_SERIAL_NUMBER` empty to let the app select the most recently used pump. The configuration validator checks required fields, URL, region, timezone, and serial format before the service starts; it does not authenticate or connect to either service.

The CT is intentionally left in place if any step fails after creation; inspect it rather than rerunning the provisioner blindly. On success, the script prints the CT ID, container IP addresses, and service status/log commands. The app begins contacting Tandem and Nightscout after systemd starts it. A running systemd unit only confirms the service process is up, not that Tandem authentication or Nightscout uploads succeeded. SSH is enabled for root key authentication only; restrict access to the CT with your Proxmox and network firewall rules.

## Service operations

```sh
sudo pct exec <CTID> -- systemctl stop tconnectsync
sudo pct exec <CTID> -- systemctl restart tconnectsync
sudo pct exec <CTID> -- systemctl enable tconnectsync       # start automatically at container boot
sudo pct exec <CTID> -- systemctl disable tconnectsync
sudo pct exec <CTID> -- journalctl -u tconnectsync -f
```

The service runs `tconnectsync --auto-update`, which keeps polling upstream for new events. The application writes its credential cache, if enabled by upstream defaults, under `/var/lib/tconnectsync/.config/tconnectsync/`; that directory is private to the service account and persists across service restarts and package updates.

## Update the upstream application

From the Proxmox node, use `pct exec` to update the upstream package inside the container:

```sh
sudo pct exec <CTID> -- bash /opt/tconnectsync-deployment/scripts/update.sh
```

It upgrades the PyPI package in the isolated virtual environment and restarts the service. This updates only the upstream application installed in the container; it does not change this deployment repository or the upstream GitHub repository.

To update these deployment files, pull the private repository on the Proxmox node, then use its host-side updater to send the latest files into the running CT and rerun the installer. Existing configuration is preserved:

```sh
cd /path/to/tconnectsync-proxmox
git pull --ff-only
sudo bash scripts/update-container.sh <CTID>
```

The installer preserves an existing local configuration file and does not print its contents.

## Uninstall

Stop and disable the service inside the CT:

```sh
sudo pct exec <CTID> -- systemctl disable --now tconnectsync
```

This intentionally does not destroy the container or delete its data. If you later decide to remove the CT, verify the CT ID and delete it through the Proxmox UI or `pct destroy <CTID>`; that removes the configuration, credential cache, and all other data in that container.

## Troubleshooting

- **Template catalog unavailable:** check Proxmox node DNS/internet and configured Proxmox repositories; run `pveam update` and `pveam available --section system` on the node.
- **Installer download fails:** the bootstrap first downloads a pinned, SHA-256-verified archive from `codeload.github.com`, then falls back to individually pinned files from `raw.githubusercontent.com`. If both hosts are blocked, no provisioning command runs and no CT is created; allow HTTPS access to either host and retry.
- **Template download/storage error:** verify that the template storage supports `vztmpl` content and the root filesystem storage supports container disks (`rootdir` content). These are often different storages.
- **CT fails to start or has no address:** inspect `pct status <CTID>`, `pct config <CTID>`, and the selected bridge, gateway, DHCP service, and firewall rules.
- **Service failed:** run `pct exec <CTID> -- systemctl status tconnectsync --no-pager` and `pct exec <CTID> -- journalctl -u tconnectsync -n 100 --no-pager`. Check local config permissions and spelling without sharing secrets or logs publicly.
- **Config validation failed:** run `pct exec <CTID> -- /opt/tconnectsync/venv/bin/python /usr/local/libexec/tconnectsync/check-config.py`. This makes no network requests.
- **Tandem or Nightscout API errors:** confirm region, timezone, account access, URL, secret, and outbound HTTPS. Avoid repeated service restarts during a provider outage; the app already retries transient errors.

## Scope and safety

This is a deployment companion, not a fork of tconnectsync. It installs the upstream package published on PyPI and uses its documented environment variables and `--auto-update` mode. Review upstream releases before applying updates. Synchronization sends Tandem pump data to the Nightscout instance you configure; verify that destination and your enabled upstream synchronization features are appropriate for your account.

## Validate this package

The local configuration checks can be tested without real credentials or network access:

```sh
python3 -m unittest discover -s tests -v
bash -n scripts/provision-proxmox.sh scripts/update-container.sh scripts/install-debian.sh scripts/update.sh
```
