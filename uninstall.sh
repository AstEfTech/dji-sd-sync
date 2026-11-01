#!/bin/sh
# Removes the dji-import service. Copied files are left untouched.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "error: run as root: sudo $0" >&2; exit 1; }

rm -f /etc/udev/rules.d/99-dji-sd.rules /etc/systemd/system/dji-import@.service
rm -rf /usr/local/lib/dji-import

systemctl daemon-reload
udevadm control --reload-rules
echo "Uninstalled."
