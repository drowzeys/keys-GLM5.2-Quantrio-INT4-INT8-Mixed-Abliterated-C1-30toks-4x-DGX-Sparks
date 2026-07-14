#!/usr/bin/env bash
# Preflight before long downloads / launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

FAILS=0
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
ok()  { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; }

say "Preflight — $(hostname -s)"

for c in git docker curl python3 bash rsync ssh; do
  if command -v "$c" >/dev/null 2>&1; then ok "cmd $c"; else bad "missing $c"; fi
done
if command -v hf >/dev/null 2>&1 || command -v huggingface-cli >/dev/null 2>&1; then
  ok "huggingface CLI (hf or huggingface-cli)"
else
  bad "need hf or huggingface-cli  (pip install -U 'huggingface_hub[cli]')"
fi

# Disk under WEIGHTS_DIR
mkdir -p "$WEIGHTS_DIR" 2>/dev/null || true
avail_kb=$(df -Pk "$WEIGHTS_DIR" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${avail_kb:-}" ]; then
  avail_gb=$((avail_kb / 1024 / 1024))
  if [ "$avail_gb" -ge 420 ]; then
    ok "disk free ~${avail_gb} GiB at $WEIGHTS_DIR"
  elif [ "$avail_gb" -ge 50 ]; then
    warn "disk free ~${avail_gb} GiB at $WEIGHTS_DIR (need ~420 GiB for full ablit tree)"
  else
    bad "disk free ~${avail_gb} GiB at $WEIGHTS_DIR — need ~420 GiB"
  fi
fi

# Docker
if docker info >/dev/null 2>&1; then ok "docker daemon"; else bad "docker not usable (group/socket?)"; fi

# IB device (warn only — some test beds use TCP)
if [ -d /dev/infiniband ]; then ok "/dev/infiniband present"; else warn "/dev/infiniband missing — NCCL may fall back to TCP (~half tok/s)"; fi

# HF token
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
if [ -n "$HF_TOKEN" ]; then
  ok "HF_TOKEN set"
elif [ "${SKIP_DOWNLOAD:-0}" = "1" ]; then
  ok "SKIP_DOWNLOAD=1 (no HF_TOKEN required if tree present)"
elif [ -f "$ABLIT_DIR/config.json" ]; then
  warn "HF_TOKEN unset but $ABLIT_DIR looks present — download step may skip/resume"
else
  bad "HF_TOKEN unset and no ablit tree at $ABLIT_DIR — export HF_TOKEN after accepting the HF gate"
fi

# Nodes / SSH
if [ "${#NODES_ARR[@]}" -eq 0 ]; then
  warn "NODES not set — multi-node fanout/launch will fail until you set recipe/cluster.env"
  warn "  cp recipe/cluster.env.example recipe/cluster.env && edit NODES=..."
else
  ok "NODES (${#NODES_ARR[@]}): ${NODES_ARR[*]}"
  if [ "${#NODES_ARR[@]}" -lt 4 ]; then
    warn "standing recipe is TP=4 (4 nodes); got ${#NODES_ARR[@]}"
  fi
  # SSH to workers (not head if head is local)
  for ip in "${NODES_ARR[@]:1}"; do
    if remote "$ip" "true" 2>/dev/null; then
      ok "ssh $(node_user "$ip")@$ip"
    else
      bad "ssh failed: $(node_user "$ip")@$ip  (fix-based auth required)"
    fi
  done
fi

# Fabric
if [ -n "${NCCL_IB_HCA:-}" ] && [ -n "${NCCL_SOCKET_IFNAME:-}" ]; then
  ok "fabric HCA=$NCCL_IB_HCA ifname=$NCCL_SOCKET_IFNAME gid=${NCCL_IB_GID_INDEX:-3}"
else
  warn "fabric not set — run: bash scripts/detect_fabric.sh --write"
fi

# Kernels source in repo
nker=$(ls "$ROOT/kernels"/*.py 2>/dev/null | wc -l | tr -d ' ')
if [ "${nker:-0}" -ge 10 ]; then ok "repo kernels/ ($nker py)"; else bad "repo kernels/ incomplete ($nker)"; fi

say "Preflight result"
if [ "$FAILS" -eq 0 ]; then
  printf '\033[1;32mPASS preflight\033[0m\n'
  exit 0
fi
printf '\033[1;31mFAIL preflight — %s issue(s)\033[0m\n' "$FAILS"
echo "Fix cluster.env / tools / HF_TOKEN, then re-run."
exit 1
