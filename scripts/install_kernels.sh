#!/usr/bin/env bash
# Install CosmicRaisins / Tony sparse-MLA kernels to $KERNELS_DIR (default ~/glm-triton).
# launch-keyspark.sh bind-mounts these into the container at serve time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$ROOT/kernels}"
DEST="${KERNELS_DIR:-$HOME/glm-triton}"

[ -d "$SRC" ] || { echo "ERROR: missing $SRC (clone full repo)" >&2; exit 1; }
mkdir -p "$DEST"
cp -a "$SRC"/*.py "$DEST/"
n=$(ls "$DEST"/*.py 2>/dev/null | wc -l | tr -d ' ')
echo "Installed $n kernel modules → $DEST"
ls -1 "$DEST"/*.py | xargs -n1 basename
[ "$n" -ge 10 ] || { echo "ERROR: expected ≥10 .py files" >&2; exit 1; }
echo "OK — set KERNELS_DIR=$DEST if non-default"
