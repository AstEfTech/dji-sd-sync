#!/bin/sh
# Sorts DJI files on an SD card into YYYY-MM-DD_ folders and copies them to a local folder.
# Pure POSIX sh, no dependencies beyond basic utilities (cp, mv, mkdir, wc, sync).
#
#   dji_import.sh [-s DCIM] [-d DEST]
#   DJI_SOURCE / DJI_DEST - the same settings via environment variables
set -eu

SOURCE=${DJI_SOURCE:-/mnt/sd/DCIM}
DEST=${DJI_DEST:-$HOME/storage/dji}

while getopts s:d: opt; do
    case $opt in
        s) SOURCE=$OPTARG ;;
        d) DEST=$OPTARG ;;
        *) echo "usage: $0 [-s DCIM] [-d DEST]" >&2; exit 2 ;;
    esac
done

log() { printf '%s\n' "$*"; }

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

# date_dir_name DJI_20241015... -> prints 2024-10-15_ ; returns 1 if not a dated DJI file
date_dir_name() {
    case $1 in DJI_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;; *) return 1 ;; esac
    s=${1#DJI_}
    y=$(printf %.4s "$s")
    rest=${s#????}
    m=$(printf %.2s "$rest")
    rest=${rest#??}
    d=$(printf %.2s "$rest")
    is_valid_date "$y" "$m" "$d" || return 1
    printf '%s-%s-%s_' "$y" "$m" "$d"
}

# group_by_date DIR - moves DJI_YYYYMMDD* files from DIR into DIR/YYYY-MM-DD_/
group_by_date() {
    for f in "$1"/*; do
        [ -f "$f" ] || continue
        name=${f##*/}
        if sub=$(date_dir_name "$name"); then
            mkdir -p "$1/$sub"
            mv -- "$f" "$1/$sub/$name"
            log "move $f -> $1/$sub/$name"
        else
            log "skip $name: not a dated DJI file"
        fi
    done
}

# copy_file SRC DST -> 0 if copied, 1 if already present with the same size
copy_file() {
    if [ -f "$2" ] && [ "$(wc -c < "$1")" -eq "$(wc -c < "$2")" ]; then
        return 1
    fi
    # copy via .part so an incomplete file never looks finished
    cp -p -- "$1" "$2.part"
    mv -f -- "$2.part" "$2"
    log "copy $1 -> $2"
}

[ -d "$SOURCE" ] || { log "$SOURCE not found -> not a DJI card, nothing to do"; exit 0; }

copied=0 skipped=0 found=0
for card_dir in "$SOURCE"/DJI_*; do
    [ -d "$card_dir" ] || continue
    found=1
    group_by_date "$card_dir"
    # copy every dated folder: if a previous run was interrupted after sorting,
    # the files still get copied; already-copied ones are skipped by size
    for dated in "$card_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_; do
        [ -d "$dated" ] || continue
        sub=${dated##*/}
        mkdir -p "$DEST/$sub"
        for f in "$dated"/*; do
            [ -f "$f" ] || continue
            if copy_file "$f" "$DEST/$sub/${f##*/}"; then
                copied=$((copied + 1))
            else
                skipped=$((skipped + 1))
            fi
        done
    done
done

[ "$found" -eq 1 ] || { log "No DJI_* folders in $SOURCE -> nothing to do"; exit 0; }
sync
log "Done: copied $copied, already present $skipped"
