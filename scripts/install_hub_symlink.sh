#!/usr/bin/env bash
# Install the hub path name that serve/launch-keyspark.sh actually uses.
#
# Launcher mounts WEIGHTS_DIR=/var/tmp/models as /cache/huggingface and runs:
#   vllm serve /cache/huggingface/hub/glm52-int4-int8mix
#
# So the host path MUST be:
#   /var/tmp/models/hub/glm52-int4-int8mix  ->  ../glm52-int4-int8mix-abliterated
#
# NOT glm52-int4-int8mix-abliterated under hub/ (fanout used to create that wrong name).
set -euo pipefail

WEIGHTS_DIR="${WEIGHTS_DIR:-/var/tmp/models}"
ABLIT_DIR="${ABLIT_DIR:-$WEIGHTS_DIR/glm52-int4-int8mix-abliterated}"
HUB_NAME="${HUB_NAME:-glm52-int4-int8mix}"
HUB_DIR="$WEIGHTS_DIR/hub"
HUB_LINK="$HUB_DIR/$HUB_NAME"

if [ ! -f "$ABLIT_DIR/config.json" ]; then
  echo "ERROR: ablit tree missing config.json at $ABLIT_DIR" >&2
  echo "  Download first: bash scripts/oneshot_install_weights.sh" >&2
  exit 1
fi

mkdir -p "$HUB_DIR"
# Relative link so the tree is relocatable under WEIGHTS_DIR
rel_target="../$(basename "$ABLIT_DIR")"
ln -sfn "$rel_target" "$HUB_LINK"

# Remove confusing wrong name if present as a dangling or wrong extra link
WRONG="$HUB_DIR/glm52-int4-int8mix-abliterated"
if [ -L "$WRONG" ] || [ -e "$WRONG" ]; then
  # keep if it also points at ablit; still not what launcher uses
  echo "note: $WRONG exists (launcher does NOT use this name)"
fi

echo "hub symlink:"
ls -la "$HUB_LINK"
echo "resolves to: $(readlink -f "$HUB_LINK")"

# quick self-check
if [ ! -f "$HUB_LINK/config.json" ]; then
  echo "ERROR: hub link does not expose config.json" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/scripts/verify_ablit_weights.py" ]; then
  python3 "$ROOT/scripts/verify_ablit_weights.py" --dir "$ABLIT_DIR" --hub "$HUB_LINK" || exit 1
fi

echo "OK — launcher path ready: $HUB_LINK"
echo "    (container: /cache/huggingface/hub/$HUB_NAME)"
