#!/usr/bin/env bash
# ============================================================================
# 🚨 REQUIRED ONE-SHOT — firm standing abliterated GLM-5.2 Quantrio weights
# ============================================================================
# IMPORTANT (agents + humans):
#   This is the ONLY supported install path for published refusal-bypass weights.
#   Follow exact steps. Do not improvise downloads or hub paths.
#   Skipping this script is the #1 reason users report "full stock refusals".
#
# Do NOT:
#   - download QuantTrio stock and serve it as ablit
#   - re-project without a direction tensor (ours is not published)
#   - invent hub names other than glm52-int4-int8mix
#   - skip verify_ablit_weights.py
#
# What it does:
#   1) hf download drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated  (~405 GiB)
#   2) verify the 28 dirty firm shards (size; optional --sha256)
#   3) install hub symlink name the launcher actually uses: glm52-int4-int8mix
#   4) optional: fanout full tree (or dirty shards) to worker IPs
#
# Usage:
#   bash scripts/oneshot_install_weights.sh
#   bash scripts/oneshot_install_weights.sh --sha256
#   WORKERS="10.100.10.1 10.100.10.2 10.100.10.3" bash scripts/oneshot_install_weights.sh --fanout
#   SKIP_DOWNLOAD=1 bash scripts/oneshot_install_weights.sh   # already downloaded
#
# Docs: INSTALL.md · README.md (top)
#
# After this:
#   SPEED=0 MAX_NUM_SEQS=4 MTP_K=4 UTIL=0.86 MAX_MODEL_LEN=128000 ./serve/launch-keyspark.sh
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster
HF_REPO="${HF_REPO:-drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated}"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-0}"
DO_FANOUT=0
DO_SHA=0
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"

for a in "$@"; do
  case "$a" in
    --fanout) DO_FANOUT=1 ;;
    --sha256) DO_SHA=1 ;;
    --skip-download) SKIP_DOWNLOAD=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $a (use --fanout --sha256 --skip-download)" >&2
      exit 2
      ;;
  esac
done

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

printf '\n\033[1;33m🚨 REQUIRED ONE-SHOT — follow exact steps (do not improvise)\033[0m\n'
printf '   Repo: INSTALL.md\n'
printf '   Goal: firm standing ablit weights with verify PASS (not QuantTrio stock)\n'

say "1/4  HF download (gated) → $ABLIT_DIR"
if [ "$SKIP_DOWNLOAD" = "1" ]; then
  echo "SKIP_DOWNLOAD=1 — not fetching"
else
  if [ -f "$ABLIT_DIR/config.json" ] && [ -f "$ABLIT_DIR/model-00100-of-00124.safetensors" ]; then
    echo "tree already present; re-run will resume/update via hf download"
  fi
  mkdir -p "$ABLIT_DIR"
  if command -v hf >/dev/null 2>&1; then
    HF_CMD=(hf download "$HF_REPO" --local-dir "$ABLIT_DIR")
  elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_CMD=(huggingface-cli download "$HF_REPO" --local-dir "$ABLIT_DIR")
  else
    die "need 'hf' or 'huggingface-cli' (pip install -U huggingface_hub)"
  fi
  if [ -n "$HF_TOKEN" ]; then
    export HF_TOKEN HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
  fi
  echo "Running: ${HF_CMD[*]}"
  echo "Note: repo is gated — accept Responsible Use on HF first."
  "${HF_CMD[@]}" || die "hf download failed (auth / gate / disk?)"
fi

[ -f "$ABLIT_DIR/config.json" ] || die "missing $ABLIT_DIR/config.json after download"

say "2/4  Verify dirty ablit shards (not stock)"
VERIFY=(python3 "$ROOT/scripts/verify_ablit_weights.py" --dir "$ABLIT_DIR")
if [ "$DO_SHA" = "1" ]; then
  VERIFY+=(--sha256)
fi
"${VERIFY[@]}" || die "weight verification failed — do NOT serve this tree"

say "3/4  Hub symlink for launcher (CRITICAL name)"
bash "$ROOT/scripts/install_hub_symlink.sh"
# re-verify with hub path (install_hub_symlink already ran size verify)
HUB_VERIFY=(python3 "$ROOT/scripts/verify_ablit_weights.py" --dir "$ABLIT_DIR" --hub "$WEIGHTS_DIR/hub/glm52-int4-int8mix")
[ "$DO_SHA" = "1" ] && HUB_VERIFY+=(--sha256)
"${HUB_VERIFY[@]}"

say "4/4  Fanout (optional)"
if [ "$DO_FANOUT" = "1" ]; then
  normalize_nodes
  if [ -z "${WORKERS:-}" ]; then
    die "fanout requested but WORKERS/NODES empty — set NODES in recipe/cluster.env (head first)"
  fi
  export WORKERS WEIGHTS_DIR ABLIT_DIR SSH_USER SSH_KEY
  bash "$ROOT/scripts/fanout_ablit.sh" || die "fanout failed"
else
  echo "Skipping fanout (pass --fanout with NODES=... for multi-node)."
  echo "On EVERY rank you must have the same ablit tree + hub symlink."
fi

say "Post-check diagnosis (this host)"
bash "$ROOT/scripts/diagnose_install.sh" || die "diagnose_install failed after oneshot"

printf '\n\033[1;32mPASS — firm standing ablit weights ready on this host\033[0m\n\n'
cat <<EOF
Tree:  $ABLIT_DIR
Hub:   $WEIGHTS_DIR/hub/glm52-int4-int8mix  →  abliterated
Serve: /cache/huggingface/hub/glm52-int4-int8mix   (inside container)

Next (image + kernels must already exist — see image/README.md):

  # after cluster.env is set:
  bash $ROOT/serve/launch-keyspark.sh

Probes for refusal bypass: enable_thinking=false (see results/serve_speed1_standing.json).

If users report partial (<100%) bypass after this PASS:
  • run diagnose on EVERY rank:  bash scripts/diagnose_install.sh
  • force thinking OFF in the client (INSTALL.md (thinking off + full fanout))
  • re-fanout if any worker still FAIL

Do NOT re-run project_residual.py for standing bypass — direction tensor is not
published; HF tree above is the standing recipe.
EOF
