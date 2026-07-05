#!/usr/bin/env bash
#
# One-time migration: move user uploads out of the old combined
# `public-content` volume and into a dedicated `uploads` volume, ahead of the
# compose change that stops shadowing all of public/ with a volume.
#
# Safe by design: this copies data and NEVER deletes the old volume. You remove
# the old volume by hand only after verifying the site works post-cutover.
#
# Run from the project directory (where the compose files live), e.g.:
#   ./scripts/migrate-uploads-volume.sh
#
set -euo pipefail

PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
OLD_VOL="${PROJECT}_public-content"
NEW_VOL="${PROJECT}_uploads"

echo ">> project:       $PROJECT"
echo ">> source volume: $OLD_VOL"
echo ">> target volume: $NEW_VOL"
echo

if ! docker volume inspect "$OLD_VOL" >/dev/null 2>&1; then
  echo "!! Source volume '$OLD_VOL' not found." >&2
  echo "   Check the project name (override with COMPOSE_PROJECT_NAME=...)." >&2
  echo "   Available volumes:" >&2
  docker volume ls --format '   {{.Name}}' >&2
  exit 1
fi

# 1. AUDIT — show everything in the old volume. Anything here that is NOT
#    'uploads/' is a runtime-added file (e.g. a hand-dropped backgrounds/ dir)
#    that this script will NOT migrate. If you see such dirs, commit them to
#    public/ in the repo instead so they bake into the image.
echo ">> Auditing contents of $OLD_VOL ..."
docker run --rm -v "$OLD_VOL":/data:ro alpine sh -c '
  echo "   top-level entries:"; ls -la /data;
  echo; echo "   directories:"; find /data -maxdepth 1 -mindepth 1 -type d;
  echo; echo "   uploads file count: $(find /data/uploads -type f 2>/dev/null | wc -l)"
'
echo
read -r -p ">> Proceed to copy uploads/ into $NEW_VOL? [y/N] " ans
[ "$ans" = "y" ] || { echo "aborted."; exit 0; }

# 2. Create the target volume (no-op if it already exists). Naming it
#    ${PROJECT}_uploads means `docker compose up` will adopt this exact volume.
docker volume create "$NEW_VOL" >/dev/null

# 3. Copy uploads across, preserving structure, permissions and timestamps.
echo ">> Copying uploads/ -> $NEW_VOL ..."
docker run --rm \
  -v "$OLD_VOL":/old:ro \
  -v "$NEW_VOL":/new \
  alpine sh -c '
    if [ -d /old/uploads ]; then
      cp -a /old/uploads/. /new/
      echo "   copied $(find /new -type f | wc -l) files"
    else
      echo "   no uploads/ dir in source — nothing to copy"
    fi
  '

echo
echo ">> Done. The old volume '$OLD_VOL' is UNTOUCHED."
echo "   Next: deploy with the new compose, verify uploads still render, then:"
echo "     docker volume rm $OLD_VOL"
