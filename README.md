# dji-sd-sync

Automatic import of DJI footage from an SD card on Linux. Insert the card and the files are sorted by date and copied to a local folder. Pure POSIX sh + udev + systemd, no dependencies.

## What it does

1. Looks for `DCIM/DJI_*` on the card.
2. Sorts `DJI_YYYYMMDD…` files into `YYYY-MM-DD_` subfolders on the card itself. Dates are properly validated (leap years, month 13, etc.); unrelated files stay where they are.
3. Copies all dated folders to the destination folder, keeping the same structure:
   - via a temporary `.part` file and `mv`, so an incomplete file never looks finished;
   - a file with the same size is skipped, so re-running is safe and picks up whatever was not copied yet;
   - file modification times are preserved.
4. Runs `sync`. **Files on the card are never deleted.**

```
card:  DCIM/DJI_001/DJI_20241015100000_0001_D.MP4
 ->    DCIM/DJI_001/2024-10-15_/DJI_20241015100000_0001_D.MP4
 ->    <DEST>/2024-10-15_/DJI_20241015100000_0001_D.MP4
```

## Manual run

```sh
sh dji_import.sh -s /mnt/sd/DCIM -d ~/storage/dji
```

Or use the `DJI_SOURCE` and `DJI_DEST` environment variables. Defaults: `/mnt/sd/DCIM` and `~/storage/dji`.

## Installing as a service

```sh
sudo ./install.sh -u your_username -d /home/your_username/storage/dji
```

| Flag | Meaning | Default |
|------|---------|---------|
| `-u USER` | user to copy as (owner of the files) | the user who invoked `sudo` |
| `-d DEST` | destination folder, absolute path | `~USER/storage/dji` |
| `-U UUID` | react only to the card with this UUID (`blkid /dev/sdX1`) | any vfat/exfat card |

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

Uninstall (copied files are left untouched):

```sh
sudo ./uninstall.sh
```

## How it works

- udev detects a `vfat`/`exfat` partition appearing (`sdX1` from a USB card reader or `mmcblkXpY` from a built-in slot) and starts `dji-import@<device>.service`.
- The unit mounts the partition at `/mnt/sd-<device>` with the user's `uid`/`gid`, runs the script, then unmounts and removes the mount point. This happens on failure too.
- If the device is already mounted (desktop automount, `/boot` on an SD card), the unit fails and touches nothing. On a desktop, disable automounting for this card or use the manual run.
- The run time limit is 2 hours, which is enough for large cards.
- If the card is pulled mid-copy, the unit stops; the next time the card is inserted, the remaining files are copied.

## Limitations

- A card without a partition table (formatted as a whole device, `/dev/sdb`) is not matched by the rule.
- Skipping is decided by file size only.
- Requires `systemd`, `udev`, `util-linux` (`mount`, `findmnt`) and a user with write access to `DEST`.
