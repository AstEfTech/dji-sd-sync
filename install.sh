#!/bin/sh
# Installs dji-import as a service: a udev rule plus a templated systemd unit.
#
#   sudo ./install.sh [-u USER] [-d DEST] [-U UUID]
#     -u USER  user to copy as (default: the user who invoked sudo)
#     -d DEST  destination folder (default: ~USER/storage/dji)
#     -U UUID  react only to the card with this UUID (blkid /dev/sdX1); without it, any vfat/exfat card
set -eu

LIBDIR=/usr/local/lib/dji-import
UNIT=/etc/systemd/system/dji-import@.service
RULES=/etc/udev/rules.d/99-dji-sd.rules

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"
here=$(cd "$(dirname "$0")" && pwd)

USER_NAME=${SUDO_USER:-}
DEST=
UUID=
while getopts u:d:U: opt; do
    case $opt in
        u) USER_NAME=$OPTARG ;;
        d) DEST=$OPTARG ;;
        U) UUID=$OPTARG ;;
        *) die "usage: $0 [-u USER] [-d DEST] [-U UUID]" ;;
    esac
done

[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || die "specify the target user with -u USER"
id "$USER_NAME" >/dev/null 2>&1 || die "no such user: $USER_NAME"
home=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$DEST" ] || DEST=$home/storage/dji
case $DEST in /*) ;; *) die "DEST must be an absolute path" ;; esac
# values are substituted via sed into the unit - reject characters that would break the substitution
case $DEST$USER_NAME$UUID in *[\|\&\\\ \"\']*) die "spaces/quotes/|&\\ are not allowed in USER, DEST, UUID" ;; esac

for f in dji_import.sh dji-import@.service 99-dji-sd.rules; do
    [ -f "$here/$f" ] || die "missing $here/$f"
done

# create the destination up front as the target user so the permissions are theirs
su -s /bin/sh -c "mkdir -p '$DEST'" "$USER_NAME" || die "cannot create $DEST as $USER_NAME"

install -Dm755 "$here/dji_import.sh" "$LIBDIR/dji_import.sh"
sed -e "s|@USER@|$USER_NAME|g" -e "s|@DEST@|$DEST|g" -e "s|@LIBDIR@|$LIBDIR|g" \
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
