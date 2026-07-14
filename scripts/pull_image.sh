#!/usr/bin/env bash
# Pull the public standing image (SPEED=1 / C1≈30 recipe).
set -euo pipefail
# Public GHCR tags (same digest):
#   ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k
#   ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:probe-modded
IMG="${IMG:-ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k}"
LOCAL="${LOCAL_TAG:-vllm-node-tf5-glm52-b12x:probe-modded}"

echo "Pulling $IMG ..."
docker pull "$IMG"
# Alias local name used by launch-keyspark.sh
docker tag "$IMG" "$LOCAL"
docker tag "$IMG" "vllm-node-tf5-glm52-b12x:speed1-c1-30-128k" 2>/dev/null || true
echo "OK — local tags:"
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'glm52-b12x|probe-modded|speed1' | head -10
