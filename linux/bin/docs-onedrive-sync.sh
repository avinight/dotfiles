#!/usr/bin/env bash
# Nightly one-way MIRROR (sync) of ~/Documents/{textbooks,uoft} to OneDrive.
# Uses `sync --track-renames` so renames become cheap server-side moves and
# local deletions are pruned on the backup.
#
# GUARDED: if a run would delete more than MAX_DELETE files on the remote (a
# suspected mass wipe), it does NOT sync — it drops a flag file, falls back to
# additive `copy`, and stays copy-only every night until the flag is removed.
set -uo pipefail

FLAGDIR="/home/friedrice/.config/docs-sync"; mkdir -p "$FLAGDIR"
MAX_DELETE="${MAX_DELETE:-500}"
COMMON=(--track-renames --fast-list --transfers=4 --checkers=16 --retries=5 --low-level-retries=10
        --exclude ".DS_Store" --exclude "._*" --log-level INFO --stats=5m --stats-one-line)

notify() { command -v notify-send >/dev/null 2>&1 && \
  notify-send -u critical "Docs backup: mass-deletion guard tripped" "$1" 2>/dev/null || true; }

sync_pair() {
  local name="$1" src="$2" dst="$3" flag="$FLAGDIR/$1.copyonly"
  echo "=== $name: $src -> $dst  $(date -Is) ==="
  if [[ -e "$flag" ]]; then
    echo "!!! COPY-ONLY LOCKDOWN ($flag) — mirror disabled, additive copy only. 'rm $flag' to re-enable."
    rclone copy "$src" "$dst" "${COMMON[@]}"; return
  fi
  local dry delc
  dry="$(rclone sync "$src" "$dst" "${COMMON[@]}" --dry-run 2>&1)"
  delc="$(printf '%s\n' "$dry" | grep -c 'Skipped delete as --dry-run is set' || true)"
  echo "would delete: $delc file(s)  (threshold MAX_DELETE=$MAX_DELETE)"
  if (( delc > MAX_DELETE )); then
    echo "!!! MASS WIPE SUSPECTED for $name: $delc > $MAX_DELETE. NOT syncing; additive copy instead."
    { echo "Docs OneDrive sync mass-deletion guard tripped for '$name'."
      echo "date: $(date -Is)"
      echo "a sync would have deleted $delc files on the backup (threshold $MAX_DELETE)."
      echo "Locked to copy-only (no deletions) nightly. If intended, resume mirror with:"
      echo "    rm '$flag'"
      echo; echo "Sample of files a sync would delete from the backup:"
      printf '%s\n' "$dry" | grep 'Skipped delete as --dry-run is set' \
        | sed -E 's/.*INFO *: //; s/: Skipped delete.*//' | head -40
    } > "$flag"
    notify "$name: $delc deletions (>$MAX_DELETE). Locked to copy-only. See $flag"
    rclone copy "$src" "$dst" "${COMMON[@]}"
  else
    rclone sync "$src" "$dst" "${COMMON[@]}" --max-delete "$MAX_DELETE"
  fi
}

echo "=== docs-onedrive-sync starting $(date -Is) ==="
sync_pair Library         "/home/friedrice/Documents/Library"        "remote:School/Library"
sync_pair Reading         "/home/friedrice/Documents/Reading"        "remote:School/Reading"
sync_pair "Sheet Music"   "/home/friedrice/Documents/Sheet Music"    "remote:School/Sheet Music"
sync_pair "Recovery Codes" "/home/friedrice/Documents/Recovery Codes" "remote:Life/Documents/Recovery Codes"
sync_pair uoft            "/home/friedrice/Documents/uoft"           "remote:School/uoft"
echo "=== docs-onedrive-sync finished $(date -Is) ==="
