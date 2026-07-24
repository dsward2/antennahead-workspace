#!/usr/bin/env bash
# Clones (or updates) every repo listed in repos.txt as a sibling of this
# umbrella repo's parent directory, e.g.:
#
#   working-directory/
#     antennahead-workspace/   <- this repo
#     AntennaHead/
#     LiveAudioServer/
#     ControlBooth/
#     PipelineHelpers/
#     antennahead-librtlsdr/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/repos.txt"
DEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

while read -r name url ref; do
  [[ -z "$name" || "$name" == \#* ]] && continue

  target="$DEST_ROOT/$name"

  if [[ -d "$target/.git" ]]; then
    echo "== $name: already cloned, fetching =="
    git -C "$target" fetch origin "$ref"
  else
    echo "== $name: cloning =="
    git clone --branch "$ref" "$url" "$target"
  fi
done < "$MANIFEST"

echo "Done. Repos are siblings of: $DEST_ROOT"
