# dji-sd-sync

Automatic import of DJI footage from an SD card on Linux. Insert the card and the files are sorted by date and copied to a local folder. Pure POSIX sh + udev + systemd, no dependencies.

## What it does

1. Looks for `DCIM/DJI_*` on the card.
2. Sorts `DJI_YYYYMMDD…` files into `YYYY-MM-DD` subfolders on the card itself. Dates are properly validated (leap years, month 13, etc.); unrelated files stay where they are.
3. Copies only the folders that received loose files in this run (folders sorted by earlier runs are not touched), keeping the same structure:
   - via a temporary `.part` file and `mv`, so an incomplete file never looks finished;
   - a file with the same size is skipped;
   - file modification times are preserved.
4. Runs `sync`. **Files on the card are never deleted.**
5. Writes a timestamped log to `log/import.log` next to the script (`DJI_LIBDIR/log` when installed) and to stdout; errors are logged as `ERROR: …`.

```
card:  DCIM/DJI_001/DJI_20241015100000_0001_D.MP4
 ->    DCIM/DJI_001/2024-10-15/DJI_20241015100000_0001_D.MP4
 ->    <DEST>/2024-10-15/DJI_20241015100000_0001_D.MP4
```

## Manual run

```sh
sh dji_import.sh -s /mnt/sd/DCIM -d ~/storage/dji
```

Without flags it uses `DJI_SOURCE` and `DJI_DEST` from `.env`; flags override them.

## Configuration

All settings live in `.env`, which is not tracked by git. Create it from the template with `cp .env.example .env` and **edit it before installing**: set at least `DJI_USER` and `DJI_DEST`.

| Variable | Meaning | Required / default |
|----------|---------|--------------------|
| `DJI_USER` | user the import runs as (owner of the copied files), not root | **required** |
| `DJI_DEST` | destination folder, absolute path | **required** |
| `DJI_UUID` | react only to the card with this UUID (`blkid /dev/sdX1`) | empty = any vfat/exfat card |
| `DJI_SOURCE` | DCIM folder on the card, for manual runs | `/mnt/sd/DCIM` |
| `DJI_TIMEOUT` | run time limit of one import | `2h` |
| `DJI_MOUNT_PREFIX` | mount point prefix (device name is appended) | `/mnt/sd-` |
| `DJI_LIBDIR` | where the script is installed (the log goes to its `log/` subfolder) | `/usr/local/lib/dji-import` |
| `DJI_UNIT` | installed systemd unit path | `/etc/systemd/system/dji-import@.service` |
| `DJI_RULES` | installed udev rule path | `/etc/udev/rules.d/99-dji-sd.rules` |

Settings are baked into the systemd unit at install time, so re-run `install.sh` after editing `.env`.

## Installing as a service

```sh
cp .env.example .env
nano .env          # set DJI_USER and DJI_DEST
sudo ./install.sh
```

What gets installed:

| File | Destination |
|------|-------------|
| `dji_import.sh` | `/usr/local/lib/dji-import/` |
| `dji-import@.service` (with your user and folder filled in) | `/etc/systemd/system/` |
| `99-dji-sd.rules` (or a rule with your UUID) | `/etc/udev/rules.d/` |

Then insert the card and watch the progress:

```sh
journalctl -f -u 'dji-import@*'
```

Uninstall (copied files are left untouched; the script and its log in `DJI_LIBDIR` are removed):

```sh
sudo ./uninstall.sh
```

## How it works

- udev detects a `vfat`/`exfat` partition appearing (`sdX1` from a USB card reader or `mmcblkXpY` from a built-in slot) and starts `dji-import@<device>.service`.
- The unit mounts the partition at `/mnt/sd-<device>` with the user's `uid`/`gid`, runs the script, then unmounts and removes the mount point. This happens on failure too.
- If the device is already mounted (desktop automount, `/boot` on an SD card), the unit fails and touches nothing. On a desktop, disable automounting for this card or use the manual run.
- The run time limit (`DJI_TIMEOUT`, 2 hours by default) is enough for large cards.
- If the card is pulled mid-copy, the unit stops. Files already sorted into a dated folder on the card are not copied again automatically; copy them manually or move them back out of the folder first.

## Limitations

- A card without a partition table (formatted as a whole device, `/dev/sdb`) is not matched by the rule.
- Skipping is decided by file size only.
- Requires `systemd`, `udev`, `util-linux` (`mount`, `findmnt`) and a user with write access to `DEST`.
