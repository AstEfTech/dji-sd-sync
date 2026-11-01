#!/bin/sh
# Installs dji-import as a service: a udev rule plus a templated systemd unit.
# All settings come from .env next to this script - edit it first, then run:
#
#   sudo ./install.sh
set -eu

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"
here=$(cd "$(dirname "$0")" && pwd)
[ -f "$here/.env" ] || die "missing $here/.env - run: cp .env.example .env, then fill in DJI_USER and DJI_DEST"
. "$here/.env"

# required
USER_NAME=${DJI_USER:-}
DEST=${DJI_DEST:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || die "set DJI_USER (not root) in .env"
[ -n "$DEST" ] || die "set DJI_DEST in .env"
id "$USER_NAME" >/dev/null 2>&1 || die "no such user: $USER_NAME"
case $DEST in /*) ;; *) die "DJI_DEST must be an absolute path" ;; esac

# optional / advanced
UUID=${DJI_UUID:-}
TIMEOUT=${DJI_TIMEOUT:-2h}
MNT=${DJI_MOUNT_PREFIX:-/mnt/sd-}
LIBDIR=${DJI_LIBDIR:-/usr/local/lib/dji-import}
UNIT=${DJI_UNIT:-/etc/systemd/system/dji-import@.service}
RULES=${DJI_RULES:-/etc/udev/rules.d/99-dji-sd.rules}
case $MNT in /*) ;; *) die "DJI_MOUNT_PREFIX must be an absolute path" ;; esac
# values are substituted via sed into the unit - reject characters that would break the substitution
case $DEST$USER_NAME$UUID$LIBDIR$TIMEOUT$MNT in *[\|\&\\\ \"\']*) die "spaces/quotes/|&\\ are not allowed in .env values" ;; esac

for f in dji_import.sh dji-import@.service 99-dji-sd.rules; do
    [ -f "$here/$f" ] || die "missing $here/$f"
done

# create the destination up front as the target user so the permissions are theirs
su -s /bin/sh -c "mkdir -p '$DEST'" "$USER_NAME" || die "cannot create $DEST as $USER_NAME"

install -Dm755 "$here/dji_import.sh" "$LIBDIR/dji_import.sh"
# the import runs as the target user, so the log folder must belong to them
install -d -m755 -o "$USER_NAME" "$LIBDIR/log"
sed -e "s|@USER@|$USER_NAME|g" -e "s|@DEST@|$DEST|g" -e "s|@LIBDIR@|$LIBDIR|g" \
    -e "s|@TIMEOUT@|$TIMEOUT|g" -e "s|@MNT@|$MNT|g" \
    "$here/dji-import@.service" > "$UNIT.tmp"
chmod 644 "$UNIT.tmp" && mv "$UNIT.tmp" "$UNIT"

if [ -n "$UUID" ]; then
    cat > "$RULES" <<EOF
# DJI SD card (UUID $UUID only)
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="$UUID", TAG+="systemd", ENV{SYSTEMD_WANTS}+="dji-import@%k.service"
EOF
    chmod 644 "$RULES"
else
    install -Dm644 "$here/99-dji-sd.rules" "$RULES"
fi

systemctl daemon-reload
udevadm control --reload-rules

echo "Installed: user=$USER_NAME dest=$DEST${UUID:+ uuid=$UUID}"
echo "Insert the card and watch: journalctl -f -u 'dji-import@*'"
