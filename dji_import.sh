#!/bin/sh
# Copies loose DJI files from an SD card to DEST/YYYY-MM-DD/, then moves each copied file into a YYYY-MM-DD folder on the card.
# Pure POSIX sh, no dependencies beyond basic utilities (cp, mv, mkdir, wc, sync).
#
#   dji_import.sh [-s DCIM] [-d DEST]
#   SD_SOURCE / SD_DEST come from .env next to this script (if present); flags override them.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
if [ -f "$here/.env" ]; then . "$here/.env"; fi

SOURCE=${SD_SOURCE:-/mnt/sd/DCIM}
DEST=${SD_DEST:-$HOME/storage/dji}

while getopts s:d: opt; do
    case $opt in
        s) SOURCE=$OPTARG ;;
        d) DEST=$OPTARG ;;
        *) echo "usage: $0 [-s DCIM] [-d DEST]" >&2; exit 2 ;;
    esac
done

# the log goes to stdout (journal) and to log/YYYY-MM-DD_HH-MM-SS.log (one file per run, named by its start time) next to this script
# (SD_LIBDIR/log when installed); if that folder is not writable, only stdout is used
LOGFILE=$here/log/$(date +%Y-%m-%d_%H-%M-%S).log
mkdir -p "$here/log" 2>/dev/null || :
log() {
    printf '%s\n' "$*"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null || :
}
fail() {
    printf 'ERROR: %s\n' "$*" >&2
    printf '%s ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null || :
    exit 1
}

# is_valid_date YYYY MM DD -> 0 if such a date exists
is_valid_date() {
    # sh function variables are global - use distinct names so the caller's m/d aren't clobbered
    case $1$2$3 in *[!0-9]*) return 1 ;; esac
    # 10# is not POSIX: strip leading zeros by hand so 08/09 aren't treated as octal
    _y=$1 _m=${2#0} _d=${3#0}
    [ "$_m" -ge 1 ] && [ "$_m" -le 12 ] && [ "$_d" -ge 1 ] || return 1
    case $_m in
        4|6|9|11) _max=30 ;;
        2) if [ $((_y % 400)) -eq 0 ] || { [ $((_y % 4)) -eq 0 ] && [ $((_y % 100)) -ne 0 ]; }
           then _max=29; else _max=28; fi ;;
        *) _max=31 ;;
    esac
    [ "$_d" -le "$_max" ]
}

# date_dir_name DJI_20241015... -> prints 2024-10-15 ; returns 1 if not a dated DJI file
date_dir_name() {
    case $1 in DJI_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;; *) return 1 ;; esac
    s=${1#DJI_}
    y=$(printf %.4s "$s")
    rest=${s#????}
    m=$(printf %.2s "$rest")
    rest=${rest#??}
    d=$(printf %.2s "$rest")
    is_valid_date "$y" "$m" "$d" || return 1
    printf '%s-%s-%s' "$y" "$m" "$d"
}

# copy_file SRC DST -> 0 if copied, 1 if already present with the same size
copy_file() {
    if [ -f "$2" ] && [ "$(wc -c < "$1")" -eq "$(wc -c < "$2")" ]; then
        return 1
    fi
    # copy via .part so an incomplete file never looks finished
    if ! cp -p -- "$1" "$2.part"; then
        rm -f -- "$2.part"
        fail "cannot copy $1 -> $2 (disk full or no write access to the destination?)"
    fi
    if [ "$(wc -c < "$1")" -ne "$(wc -c < "$2.part")" ]; then
        rm -f -- "$2.part"
        fail "size mismatch after copying $1 -> $2"
    fi
    mv -f -- "$2.part" "$2" || fail "cannot rename $2.part -> $2"
    log "copy $1 -> $2"
}

# import_dir DIR - for every loose DJI_YYYYMMDD* file in DIR: copy it to DEST/YYYY-MM-DD/,
# and only after a successful copy move it into DIR/YYYY-MM-DD/ on the card.
# An interrupted run leaves the unfinished files loose, so the next run resumes with them.
import_dir() {
    for f in "$1"/*; do
        [ -f "$f" ] || continue
        name=${f##*/}
        if ! sub=$(date_dir_name "$name"); then
            log "skip $name: not a dated DJI file"
            continue
        fi
        mkdir -p "$DEST/$sub" || fail "cannot create $DEST/$sub"
        if copy_file "$f" "$DEST/$sub/$name"; then
            copied=$((copied + 1))
        else
            skipped=$((skipped + 1))
        fi
        # the copy is safe in DEST; failing to tidy the card is not fatal, it is retried next time
        if mkdir -p "$1/$sub" && mv -- "$f" "$1/$sub/$name"; then
            log "move $f -> $1/$sub/$name"
        else
            log "WARNING: cannot move $f -> $1/$sub/$name (card write-protected?)"
            unmoved=$((unmoved + 1))
        fi
    done
}

[ -d "$SOURCE" ] || { log "$SOURCE not found -> not a DJI card, nothing to do"; exit 0; }

copied=0 skipped=0 unmoved=0 found=0
for card_dir in "$SOURCE"/DJI_*; do
    [ -d "$card_dir" ] || continue
    found=1
    import_dir "$card_dir"
done

[ "$found" -eq 1 ] || { log "No DJI_* folders in $SOURCE -> nothing to do"; exit 0; }
sync
log "Done: copied $copied, already present $skipped, not moved on the card $unmoved"
