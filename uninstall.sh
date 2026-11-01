#!/bin/sh
# Removes the dji-import service. Copied files are left untouched.
# Install locations are read from .env next to this script.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "error: run as root: sudo $0" >&2; exit 1; }

here=$(cd "$(dirname "$0")" && pwd)
if [ -f "$here/.env" ]; then . "$here/.env"; fi

systemctl stop 'dji-import@*' 2>/dev/null || :
rm -f "${DJI_RULES:-/etc/udev/rules.d/99-dji-sd.rules}" "${DJI_UNIT:-/etc/systemd/system/dji-import@.service}"
rm -rf "${DJI_LIBDIR:-/usr/local/lib/dji-import}"

systemctl daemon-reload
udevadm control --reload-rules
echo "Uninstalled."
