#!/usr/bin/env bash
# Put a freshly built engine where the app expects to find it.
#
# electron-builder copies `extras/` into Sonocles.app/Contents/extras, and the
# runtime hands PHP that location in NATIVEPHP_EXTRAS_PATH. In development the
# same variable points here, so one directory serves both and App\Support\Sidecar
# needs only one lookup.
#
# The binary is a 16 MB build product and is not committed — see php/.gitignore.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
built="$root/app/.build/release/sonocles-cli"

if [[ ! -x "$built" ]]; then
  echo "no engine at $built — run: swift build -c release --package-path app" >&2
  exit 1
fi

mkdir -p "$root/php/extras"
cp "$built" "$root/php/extras/sonocles-cli"
echo "synced $(du -h "$root/php/extras/sonocles-cli" | cut -f1) → php/extras/sonocles-cli"
