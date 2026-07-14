#!/usr/bin/env bash
# ============================================================================
# MASTER ONE-SHOT — standing GLM-5.2 Quantrio ablit on ANY 4× DGX Spark
# ============================================================================
# Spec: specs/001-oneshot-any-cluster/
#
# Usage:
#   cp recipe/cluster.env.example recipe/cluster.env   # edit NODES / SSH / fabric
#   export HF_TOKEN=hf_...
#   bash scripts/oneshot.sh                  # preflight + kernels + image + NCCL + weights
#   bash scripts/oneshot.sh --fanout         # + fanout image/kernels/NCCL/weights to workers
#   bash scripts/oneshot.sh --launch         # + SPEED=1 launch
#   bash scripts/oneshot.sh --verify         # + refusal suite (needs live serve)
#   bash scripts/oneshot.sh --all            # fanout + launch + wait + suite
#
# Env (also recipe/cluster.env):
#   NODES="head w1 w2 w3"   SSH_USER=...   SSH_KEY=...
#   WEIGHTS_DIR=/var/tmp/models   HF_TOKEN=...   SKIP_DOWNLOAD=1
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

DO_FANOUT=0
DO_LAUNCH=0
DO_VERIFY=0
SKIP_PREFLIGHT=0
for a in "$@"; do
  case "$a" in
    --fanout) DO_FANOUT=1 ;;
    --launch) DO_LAUNCH=1 ;;
    --verify) DO_VERIFY=1 ;;
    --all) DO_FANOUT=1; DO_LAUNCH=1; DO_VERIFY=1 ;;
    --skip-preflight) SKIP_PREFLIGHT=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

printf '\n\033[1;33m🚨 oneshot.sh — standing Path A (do not improvise)\033[0m\n'
printf '   Repo: %s\n' "$ROOT"
printf '   Nodes: %s\n' "${NODES:-"(unset — set recipe/cluster.env)"}"
printf '   SSH user: %s\n' "${SSH_USER}"

# Multi-node launch requires fanout
if [ "$DO_LAUNCH" = "1" ] && [ "${#NODES_ARR[@]}" -gt 1 ] && [ "$DO_FANOUT" != "1" ]; then
  warn "multi-node launch without --fanout is unsafe — enabling fanout"
  DO_FANOUT=1
fi

# 0) preflight
if [ "$SKIP_PREFLIGHT" != "1" ]; then
  say "0/7  Preflight"
  bash "$ROOT/scripts/preflight.sh" || die "preflight failed — fix issues above"
else
  say "0/7  Preflight skipped"
fi

# 1) kernels (local)
say "1/7  Install kernels → $KERNELS_DIR"
bash "$ROOT/scripts/install_kernels.sh"

# 2) image (local)
say "2/7  Pull public serve image"
bash "$ROOT/scripts/pull_image.sh"

# 3) NCCL (local)
say "3/7  Stage NCCL 2.30.4"
bash "$ROOT/scripts/stage_nccl.sh"

# 4) ablit weights + hub
say "4/7  Install abliterated weights (REQUIRED)"
ARGS=()
[ "${SKIP_DOWNLOAD:-0}" = "1" ] && ARGS+=(--skip-download)
# fanout weights handled below with full multi-artifact fanout
bash "$ROOT/scripts/oneshot_install_weights.sh" "${ARGS[@]+"${ARGS[@]}"}"

# 5) multi-node fanout (image, kernels, NCCL, weights)
if [ "$DO_FANOUT" = "1" ]; then
  say "5/7  Fanout to workers (image + kernels + NCCL + weights)"
  if [ -z "${WORKERS:-}" ]; then
    die "fanout requested but WORKERS/NODES workers empty — set NODES in recipe/cluster.env"
  fi
  bash "$ROOT/scripts/fanout_kernels.sh"
  bash "$ROOT/scripts/fanout_image.sh"
  bash "$ROOT/scripts/stage_nccl.sh" --fanout
  export WORKERS WEIGHTS_DIR ABLIT_DIR SSH_USER SSH_KEY
  bash "$ROOT/scripts/fanout_ablit.sh" || die "weight fanout failed"
else
  say "5/7  Skip fanout (pass --fanout or --all for multi-node)"
fi

# 6) diagnose head
say "6/7  Diagnose install (this host)"
bash "$ROOT/scripts/diagnose_install.sh" || die "diagnose failed — fix before launch"

# 7) optional launch SPEED=1
if [ "$DO_LAUNCH" = "1" ]; then
  say "7/7  Launch SPEED=1 (TP=${#NODES_ARR[@]})"
  if [ "${#NODES_ARR[@]}" -lt 1 ]; then
    die "NODES empty — cannot launch. Set recipe/cluster.env"
  fi
  if [ -z "${NCCL_IB_HCA:-}" ] || [ -z "${NCCL_SOCKET_IFNAME:-}" ]; then
    warn "fabric incomplete — running detect_fabric"
    bash "$ROOT/scripts/detect_fabric.sh" || true
    init_cluster
  fi
  export NODES SSH_USER SSH_KEY WEIGHTS_DIR KERNELS_DIR IMAGE NAME PORT MASTER_PORT
  export NCCL_IB_HCA NCCL_SOCKET_IFNAME GLOO_SOCKET_IFNAME NCCL_IB_GID_INDEX
  export MTP_K SPEED UTIL MAX_MODEL_LEN KV_BYTES LAYERING
  bash "$ROOT/serve/launch-keyspark.sh"

  HEAD="${HEAD:-${NODES_ARR[0]}}"
  PORT="${PORT:-8210}"
  say "Waiting for API http://$HEAD:$PORT/v1/models ..."
  for i in $(seq 1 120); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$HEAD:$PORT/v1/models" || echo 000)
    [ "$code" = "200" ] && { echo "READY after ~$((i*15))s ($i polls)"; break; }
    sleep 15
    if [ "$i" = "120" ]; then
      echo "TIMEOUT waiting for API — check: docker logs -f ${NAME:-vllm_qt200k}"
      exit 1
    fi
  done
else
  say "7/7  Skip launch (pass --launch or --all)"
fi

# optional refusal suite
if [ "$DO_VERIFY" = "1" ]; then
  say "Refusal suite (32/32 claim, thinking OFF)"
  HEAD="${HEAD:-${NODES_ARR[0]:-127.0.0.1}}"
  PORT="${PORT:-8210}"
  python3 "$ROOT/scripts/refusal_suite.py" \
    --api "http://$HEAD:$PORT/v1" --model glm-5.2 \
    --out "$ROOT/results/refusal_suite_live.json"
else
  say "Skip suite (pass --verify or --all)"
fi

printf '\n\033[1;32mPASS — oneshot complete\033[0m\n'
cat <<EOF

Standing serve (manual if you skipped --launch):
  bash serve/launch-keyspark.sh

API:  http://HEAD:8210/v1   model id: glm-5.2
Stop: bash serve/launch-keyspark.sh --stop

Config: recipe/cluster.env  (from cluster.env.example)
Fabric: bash scripts/detect_fabric.sh --write
Docs:   INSTALL.md · docs/ONE_SHOT.md · INSTALL.md (thinking off + full fanout)
Spec:   specs/001-oneshot-any-cluster/
EOF
