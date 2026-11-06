# tconnectsync on Proxmox LXC

This repository packages the upstream [`jwoglom/tconnectsync`](https://github.com/jwoglom/tconnectsync) Python application for a Debian Linux Container (LXC) on Proxmox VE. It installs the published `tconnectsync` package into an isolated Python virtual environment and runs it as a native systemd service. The upstream application is not copied or modified here.

## Proxmox prerequisites

- Create a Debian 12 or newer LXC with systemd as its init system. An unprivileged container is recommended.
- Enable start-at-boot if desired. Docker, nesting, privileged mode, USB devices, and host filesystem mounts are not required.
- Allow outbound DNS and HTTPS (TCP 443) to Tandem and your Nightscout host.
- Set the container's system timezone if you want its system logs to use that zone. Separately, `TIMEZONE_NAME` below must match the timezone configured on your pump.

## Install

Run these commands inside the new container. The deployment repository can be cloned over SSH or HTTPS by an account authorized for the private repository.

```sh
git clone https://github.com/SourceGrid-core/tconnectsync-proxmox.git
cd tconnectsync-proxmox
sudo ./scripts/install-debian.sh
```

The installer installs Debian's Python and timezone packages, creates a locked-down `tconnectsync` system account and virtual environment, installs the current `tconnectsync` release from PyPI, installs the systemd unit and a private configuration file, and enables (but does not start) the service.

Edit `/etc/tconnectsync/tconnectsync.env` locally in the container. It is installed as `root:tconnectsync` with mode `0640`; keep it that way and do not commit it, paste it into tickets, or include it in logs. The configuration names and formats are:

```ini
TCONNECT_EMAIL=
TCONNECT_PASSWORD=
TCONNECT_REGION=US
NS_URL=
NS_SECRET=
TIMEZONE_NAME=America/New_York
# Optional numeric pump serial:
# PUMP_SERIAL_NUMBER=
```

Set `TCONNECT_REGION` to `US` or `EU`. Use a timezone database name such as `America/New_York` for `TIMEZONE_NAME`, and use your pump's configured timezone. `PUMP_SERIAL_NUMBER` is optional; omit it unless you need to select a specific pump. The app otherwise selects the most recently used pump.

The service reads this file directly through systemd; do not `source` it as a shell script. Keep values on one line. If a value contains whitespace, use systemd-compatible quoting. The credentials are never needed in this deployment repository.

Check the configuration without connecting to either service, then start the synchronizer:

```sh
sudo /opt/tconnectsync/venv/bin/python /usr/local/libexec/tconnectsync/check-config.py
sudo systemctl start tconnectsync
sudo systemctl status tconnectsync --no-pager
sudo journalctl -u tconnectsync -n 100 --no-pager
```

The same configuration check runs before every service start. It checks that the required values are present, region and optional serial number are valid, the Nightscout URL is an HTTP(S) URL, and the timezone exists. It does not authenticate or contact Tandem or Nightscout. Do not share journal output without checking it for private account or health information.

## Service operations

```sh
sudo systemctl stop tconnectsync
sudo systemctl restart tconnectsync
sudo systemctl enable tconnectsync       # start automatically at container boot
sudo systemctl disable tconnectsync
sudo journalctl -u tconnectsync -f
```

The service runs `tconnectsync --auto-update`, which keeps polling upstream for new events. The application writes its credential cache, if enabled by upstream defaults, under `/var/lib/tconnectsync/.config/tconnectsync/`; that directory is private to the service account and persists across service restarts and package updates.

## Update the upstream application

From a terminal inside the container, run the companion update script:

```sh
cd /path/to/tconnectsync-proxmox
sudo ./scripts/update.sh
```

It upgrades the PyPI package in the isolated virtual environment and restarts the service. This updates only the upstream application installed in the container; it does not change this deployment repository or the upstream GitHub repository.

To update these deployment files, pull the private repository in your checkout, then rerun the installer if the service unit or configuration template changed:

```sh
cd /path/to/tconnectsync-proxmox
git pull --ff-only
sudo ./scripts/install-debian.sh
```

The installer preserves an existing local configuration file and does not print its contents.

## Uninstall

Stop and disable the unit, then remove the unit and service account data only if you no longer need them:

```sh
sudo systemctl disable --now tconnectsync
sudo rm /etc/systemd/system/tconnectsync.service
sudo systemctl daemon-reload
```

The remaining configuration and cache contain private credentials/tokens. Remove `/etc/tconnectsync` and `/var/lib/tconnectsync` yourself only after deciding you no longer need them.

## Scope and safety

This is a deployment companion, not a fork of tconnectsync. It installs the upstream package published on PyPI and uses its documented environment variables and `--auto-update` mode. Review upstream releases before applying updates. Synchronization sends Tandem pump data to the Nightscout instance you configure; verify that destination and your enabled upstream synchronization features are appropriate for your account.

## Validate this package

The local configuration checks can be tested without real credentials or network access:

```sh
python3 -m unittest discover -s tests -v
bash -n scripts/install-debian.sh scripts/update.sh
```
