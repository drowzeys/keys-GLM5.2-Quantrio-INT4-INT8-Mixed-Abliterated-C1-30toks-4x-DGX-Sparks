#!/usr/bin/env bash
# ============================================================================
# bake_image.sh — build the standing vLLM image entirely from THIS repo
# ============================================================================
# What is already in-repo (no other project clones needed for patches/mods/kernels):
#   image/mods/glm52-sm12x-sparse/run.sh     (tonyd2wild / ciprianveg / CosmicRaisins)
#   image/mods/glm52-b12x-sparse/run.sh
#   image/patches/fix-indexer-mtp-overhang.py
#   kernels/*.py                             (CosmicRaisins + standing extras)
#   image/pins.env
#
# What still needs network (cannot ship in git — multi‑GB):
#   1) eugr/spark-vllm-docker harness + vLLM source at pinned VLLM_REF
#   2) pip install b12x during the b12x mod (optional if already cached)
#
# Prefer the public GHCR image when possible:
#   bash scripts/pull_image.sh
#
# Usage:
#   bash image/bake_image.sh              # full base build + mods + patch + tags
#   bash image/bake_image.sh --mods-only  # base image already local as BASE_TAG
#   bash image/bake_image.sh --dry-run
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/image/pins.env"

MODS_ONLY=0
DRYRUN=0
for a in "$@"; do
  case "$a" in
    --mods-only) MODS_ONLY=1 ;;
    --dry-run) DRYRUN=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

WORK="${WORK_DIR:-$ROOT/.bake-work}"
KERNELS_HOST="${KERNELS_DIR_FOR_BAKE:-$ROOT/kernels}"
[ -f "$KERNELS_HOST/sparse_mla_kernels.py" ] || die "missing kernels at $KERNELS_HOST"
[ -f "$ROOT/image/mods/glm52-sm12x-sparse/run.sh" ] || die "missing sm12x mod"
[ -f "$ROOT/image/mods/glm52-b12x-sparse/run.sh" ] || die "missing b12x mod"
[ -f "$ROOT/image/patches/fix-indexer-mtp-overhang.py" ] || die "missing indexer patch"

say "Pins"
echo "  VLLM_REF=$VLLM_REF"
echo "  BASE_TAG=$BASE_TAG"
echo "  MODDED_TAG=$MODDED_TAG"
echo "  GHCR_TAG=$GHCR_TAG"
echo "  kernels=$KERNELS_HOST"

if [ "$DRYRUN" = "1" ]; then
  echo "(dry-run) would build base unless --mods-only, then apply mods+patch and tag"
  exit 0
fi

# --------------------------------------------------------------------------
# Step A: base image via eugr/spark-vllm-docker (unless --mods-only)
# --------------------------------------------------------------------------
if [ "$MODS_ONLY" = "1" ]; then
  docker image inspect "$BASE_TAG" >/dev/null 2>&1 \
    || die "BASE_TAG $BASE_TAG not present — run without --mods-only first"
  say "Skipping base build (--mods-only); using $BASE_TAG"
else
  say "Clone / update spark-vllm-docker harness"
  mkdir -p "$WORK"
  HARNESS="$WORK/spark-vllm-docker"
  if [ ! -d "$HARNESS/.git" ]; then
    git clone --depth 1 "${SPARK_VLLM_DOCKER_URL}" "$HARNESS"
  else
    git -C "$HARNESS" fetch --depth 1 origin "${SPARK_VLLM_DOCKER_REF}" || true
    git -C "$HARNESS" checkout "${SPARK_VLLM_DOCKER_REF}" 2>/dev/null || true
  fi
  say "Build base image (~35–60 min) → $BASE_TAG"
  (
    cd "$HARNESS"
    # --tf5 kept for tag/recipe compatibility (deprecated flag in newer harness)
    ./build-and-copy.sh --vllm-ref "$VLLM_REF" -t "$BASE_TAG" --tf5
  )
  docker image inspect "$BASE_TAG" >/dev/null 2>&1 || die "base build failed: $BASE_TAG missing"
fi

# --------------------------------------------------------------------------
# Step B: apply tonyd mods + indexer patch inside a patch container
# --------------------------------------------------------------------------
# Mod scripts expect kernels at /root/models/models15/glm-triton (hardcoded).
CNAME="glm52-modding-$$"
say "Start patch container $CNAME"
docker rm -f "$CNAME" 2>/dev/null || true
docker run -d --name "$CNAME" \
  -v "$KERNELS_HOST:/root/models/models15/glm-triton:ro" \
  -v "$ROOT/image/mods/glm52-sm12x-sparse:/mods/glm52-sm12x-sparse:ro" \
  -v "$ROOT/image/mods/glm52-b12x-sparse:/mods/glm52-b12x-sparse:ro" \
  -v "$ROOT/image/patches:/patches:ro" \
  "$BASE_TAG" sleep infinity

cleanup() { docker rm -f "$CNAME" 2>/dev/null || true; }
trap cleanup EXIT

say "Run glm52-sm12x-sparse mod"
docker exec "$CNAME" bash /mods/glm52-sm12x-sparse/run.sh

say "Run glm52-b12x-sparse mod"
docker exec "$CNAME" bash /mods/glm52-b12x-sparse/run.sh

say "Apply indexer MTP-overhang patch"
docker exec "$CNAME" python3 /patches/fix-indexer-mtp-overhang.py

say "Commit → $MODDED_TAG"
# Always reset ENTRYPOINT (docker commit inherits overrides otherwise)
docker commit \
  --change 'ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]' \
  --change 'CMD []' \
  "$CNAME" "$MODDED_TAG"

docker tag "$MODDED_TAG" "vllm-node-tf5-glm52-b12x:speed1-c1-30-128k" 2>/dev/null || true
docker tag "$MODDED_TAG" "$GHCR_TAG" 2>/dev/null || true
docker tag "$MODDED_TAG" "$GHCR_TAG_ALIAS" 2>/dev/null || true

say "Verify image"
docker image inspect "$MODDED_TAG" >/dev/null
docker run --rm "$MODDED_TAG" python3 -c "import b12x; print('b12x OK', b12x.__file__)" \
  || echo "WARN: b12x import check failed (Triton path may still work)"

cat <<EOF

\033[1;32mPASS — image baked\033[0m
  local:  $MODDED_TAG
  alias:  vllm-node-tf5-glm52-b12x:speed1-c1-30-128k
  ghcr:   $GHCR_TAG  (tag only; push with: docker push $GHCR_TAG)

Distribute to workers:
  bash scripts/fanout_image.sh

Or re-run oneshot (will pull GHCR if present, else use local tag):
  bash scripts/oneshot.sh --fanout
EOF
