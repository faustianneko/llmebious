#!/usr/bin/env bash
#
# Coherent backup of nmebious: a Postgres dump PLUS the uploaded files,
# captured together. These two must be kept in sync — a DB row of type 'file'
# points to a file on disk by name, so backing up one without the other yields
# broken images (dangling pointers) or invisible orphans.
#
# Usage (from the project directory):
#   ./scripts/backup.sh                      # -> ~/backups/nmebious-<stamp>/
#   BACKUP_DIR=/mnt/backups ./scripts/backup.sh
#
# Restore (rough outline):
#   DB:      docker compose ... exec -T db pg_restore -U postgres -d nmebious --clean < db.dump
#   uploads: docker run --rm -v <project>_uploads:/data -v "$PWD":/b alpine \
#              tar xzf /b/uploads.tar.gz -C /data
#
set -euo pipefail

# Support both compose v2 ("docker compose") and v1 ("docker-compose").
if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
else
  DC=(docker-compose)
fi
COMPOSE=(-f docker-compose.yml -f docker-compose.prod.yml)
PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
# After the refactor uploads live in the dedicated volume. For a pre-cutover
# backup, point this at the old combined volume:
#   UPLOADS_VOLUME=<project>_public-content ./scripts/backup.sh
UPLOADS_VOL="${UPLOADS_VOLUME:-${PROJECT}_uploads}"
DB_SERVICE="db"
DB_NAME="nmebious"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_DIR:-$HOME/backups}/nmebious-$STAMP"
mkdir -p "$DEST"

echo ">> backing up to $DEST"

# 1. Database — custom format (-Fc): compressed and restorable with pg_restore.
#    Dumps as the 'postgres' superuser over the local socket (trust auth inside
#    the container), so no password handling is needed here.
echo ">> pg_dump $DB_NAME ..."
"${DC[@]}" "${COMPOSE[@]}" exec -T "$DB_SERVICE" \
  pg_dump -U postgres -Fc "$DB_NAME" > "$DEST/db.dump"

# 2. Uploaded files — tar the uploads volume read-only.
echo ">> archiving uploads volume $UPLOADS_VOL ..."
if docker volume inspect "$UPLOADS_VOL" >/dev/null 2>&1; then
  docker run --rm \
    -v "$UPLOADS_VOL":/data:ro \
    -v "$DEST":/backup \
    alpine tar czf /backup/uploads.tar.gz -C /data .
else
  echo "!! uploads volume '$UPLOADS_VOL' not found — skipping (check project name)." >&2
fi

echo ">> done:"
ls -lh "$DEST"
