#!/usr/bin/env bash
# Pull the public standing image (SPEED=1 / C1≈30 recipe).
# If GHCR is unreachable and a local modded image already exists, keep it.
# Full offline rebuild from this repo: bash image/bake_image.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${IMG:-ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k}"
LOCAL="${LOCAL_TAG:-vllm-node-tf5-glm52-b12x:probe-modded}"

if docker image inspect "$LOCAL" >/dev/null 2>&1 && [ "${FORCE_PULL:-0}" != "1" ]; then
  echo "Local image already present: $LOCAL (set FORCE_PULL=1 to re-pull)"
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'glm52-b12x|probe-modded|speed1' | head -10
  exit 0
fi

echo "Pulling $IMG ..."
if ! docker pull "$IMG"; then
  echo "ERROR: GHCR pull failed."
  echo "  Rebuild from this repo (tonyd mods + kernels vendored):"
  echo "    bash $ROOT/image/bake_image.sh"
  exit 1
fi
docker tag "$IMG" "$LOCAL"
docker tag "$IMG" "vllm-node-tf5-glm52-b12x:speed1-c1-30-128k" 2>/dev/null || true
echo "OK — local tags:"
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'glm52-b12x|probe-modded|speed1' | head -10
