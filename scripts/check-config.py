#!/usr/bin/env python3
import os
import sys
from urllib.parse import urlparse
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


required = (
    "TCONNECT_EMAIL",
    "TCONNECT_PASSWORD",
    "NS_URL",
    "NS_SECRET",
    "TIMEZONE_NAME",
)
missing = [name for name in required if not os.environ.get(name, "").strip()]
if missing:
    print("Missing required configuration: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)

region = os.environ.get("TCONNECT_REGION", "US").strip()
if region not in ("US", "EU"):
    print("TCONNECT_REGION must be US or EU.", file=sys.stderr)
    sys.exit(1)

url = urlparse(os.environ["NS_URL"].strip())
if url.scheme not in ("http", "https") or not url.netloc:
    print("NS_URL must be an absolute HTTP(S) URL.", file=sys.stderr)
    sys.exit(1)

try:
    ZoneInfo(os.environ["TIMEZONE_NAME"].strip())
except (ZoneInfoNotFoundError, ValueError):
    print("TIMEZONE_NAME must be a valid timezone database name.", file=sys.stderr)
    sys.exit(1)

serial = os.environ.get("PUMP_SERIAL_NUMBER", "").strip()
if serial and not serial.isdecimal():
    print("PUMP_SERIAL_NUMBER must contain only digits when set.", file=sys.stderr)
    sys.exit(1)

print("Configuration is present and valid; no network connections were made.")
