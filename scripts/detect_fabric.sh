#!/usr/bin/env bash
# Detect RoCE HCA + fabric interface and optionally write recipe/cluster.env.detected
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

OUT="${1:-}"
say "Fabric detect on $(hostname -s)"

if command -v ibdev2netdev >/dev/null 2>&1; then
  echo "--- ibdev2netdev ---"
  ibdev2netdev || true
else
  warn "ibdev2netdev not found (install MLNX_OFED / rdma-core tools)"
fi

echo "--- IP addresses ---"
ip -br a 2>/dev/null || ip addr

if command -v show_gids >/dev/null 2>&1; then
  echo "--- show_gids (first 20 lines) ---"
  show_gids 2>/dev/null | head -20 || true
fi

detect_fabric_into_env
echo
echo "Proposed:"
echo "  NCCL_IB_HCA=$NCCL_IB_HCA"
echo "  NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME"
echo "  GLOO_SOCKET_IFNAME=$GLOO_SOCKET_IFNAME"
echo "  NCCL_IB_GID_INDEX=${NCCL_IB_GID_INDEX:-3}"

if [ -z "${NCCL_IB_HCA:-}" ] || [ -z "${NCCL_SOCKET_IFNAME:-}" ]; then
  die "could not auto-detect fabric — set NCCL_IB_HCA / NCCL_SOCKET_IFNAME in recipe/cluster.env"
fi

if [ "$OUT" = "--write" ] || [ "$OUT" = "-w" ]; then
  dest="$ROOT/recipe/cluster.env.detected"
  cat >"$dest" <<EOF
# Auto-detected $(date -Is) on $(hostname -s) — REVIEW before use
# Merge into recipe/cluster.env (especially NODES / SSH_USER).
NCCL_IB_HCA=$NCCL_IB_HCA
NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME
GLOO_SOCKET_IFNAME=$GLOO_SOCKET_IFNAME
NCCL_IB_GID_INDEX=${NCCL_IB_GID_INDEX:-3}
EOF
  ok "wrote $dest"
fi
