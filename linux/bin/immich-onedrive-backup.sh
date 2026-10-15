#!/usr/bin/env bash
# Backs up Immich originals + newest DB dump + profile images to OneDrive.
# Skips thumbs/ and encoded-video/ (regenerable by Immich).
#
# `upload/` uses a GUARDED SYNC:
#   - Normally `rclone sync` (mirror) so deletions in Immich are pruned on the
#     backup too and OneDrive doesn't grow forever.
#   - But if a run would delete more than MAX_DELETE files (a suspected mass
#     wipe), it does NOT sync. Instead it drops a flag file and falls back to
#     additive `rclone copy`, and STAYS in copy-only mode every night until a
#     human removes the flag. This stops an accidental/ransomware wipe from
#     propagating to the backup.
# `backups/` and `profile/` stay additive `copy` (dumps are tiny restore points).
set -uo pipefail

SRC="/home/friedrice/immich/library"
DST="remote:immich-backup"
FLAG="/home/friedrice/immich/.backup-copyonly"   # presence => copy-only lockdown
MAX_DELETE="${MAX_DELETE:-500}"                   # >this many deletions = mass wipe

COMMON=(--fast-list --transfers=4 --checkers=16 --retries=5 --low-level-retries=10
        --log-level INFO --stats=5m --stats-one-line)

notify() {  # best-effort desktop alert (KDE); never fatal
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -u critical "Immich backup: mass-deletion guard tripped" "$1" 2>/dev/null || true
}

echo "=== immich-onedrive-backup starting $(date -Is) ==="

# ---- DB dumps + profile : additive copy (FIRST) ----------------------------
# These are TINY (~125 MB) but are what you actually need to restore. Copy them
# BEFORE the huge upload sync so a timeout mid-upload never leaves the backup
# without a database. Newest dumps only (fresh nightly at 02:00).
rclone copy "$SRC/backups" "$DST/backups" "${COMMON[@]}" --max-age 72h
rclone copy "$SRC/profile" "$DST/profile" "${COMMON[@]}"

# ---- upload/ : guarded sync -------------------------------------------------
if [[ -e "$FLAG" ]]; then
  echo "!!! COPY-ONLY LOCKDOWN active ($FLAG exists) — syncing disabled, doing additive copy."
  echo "    Review it, then 'rm $FLAG' to re-enable mirror sync."
  rclone copy "$SRC/upload" "$DST/upload" "${COMMON[@]}"
else
  echo "--- dry-run: counting how many files a sync would DELETE on the backup ---"
  dry="$(rclone sync "$SRC/upload" "$DST/upload" "${COMMON[@]}" --dry-run 2>&1)"
  delcount="$(printf '%s\n' "$dry" | grep -c 'Skipped delete as --dry-run is set' || true)"
  echo "would delete: $delcount file(s)  (threshold MAX_DELETE=$MAX_DELETE)"

  if (( delcount > MAX_DELETE )); then
    echo "!!! MASS WIPE SUSPECTED: $delcount deletions > $MAX_DELETE. NOT syncing."
    {
      echo "Immich OneDrive backup tripped its mass-deletion guard."
      echo "date: $(date -Is)"
      echo "files a sync would have deleted on the backup: $delcount (threshold $MAX_DELETE)"
      echo "The backup is now LOCKED to copy-only (no deletions) every night."
      echo "If this deletion was intentional, remove this file to resume mirror sync:"
      echo "    rm '$FLAG'"
      echo
      echo "Sample of files that would have been deleted from the backup:"
      printf '%s\n' "$dry" | grep 'Skipped delete as --dry-run is set' \
        | sed -E 's/.*INFO *: //; s/: Skipped delete.*//' | head -40
    } > "$FLAG"
    notify "$delcount files would be deleted (>$MAX_DELETE). Backup locked to copy-only. See $FLAG"
    echo "--- falling back to additive copy for this run ---"
    rclone copy "$SRC/upload" "$DST/upload" "${COMMON[@]}"
  else
    echo "--- deletions within threshold: performing mirror sync ---"
    rclone sync "$SRC/upload" "$DST/upload" "${COMMON[@]}" --max-delete "$MAX_DELETE"
  fi
fi

echo "=== immich-onedrive-backup finished OK $(date -Is) ==="
