#!/usr/bin/env bash
# Shared helpers for oneshot / fanout / launch.
# shellcheck disable=SC2034
# Usage:  source "$ROOT/scripts/lib/common.sh"

if [ -z "${ROOT:-}" ]; then
  # shellcheck disable=SC2296
  _COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$_COMMON_DIR/../.." && pwd)"
fi

# ---------------------------------------------------------------------------
# Load recipe/cluster.env if present (does not override already-exported vars)
# ---------------------------------------------------------------------------
load_cluster_env() {
  local f="${CLUSTER_ENV:-$ROOT/recipe/cluster.env}"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$f"
    set +a
    echo "loaded cluster config: $f" >&2
  fi
}

# ---------------------------------------------------------------------------
# Defaults (examples only — override via cluster.env / env)
# ---------------------------------------------------------------------------
apply_cluster_defaults() {
  SSH_USER="${SSH_USER:-${USER:-$(whoami)}}"
  SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
  if [ ! -f "$SSH_KEY" ] && [ -f "$HOME/.ssh/id_rsa" ]; then
    SSH_KEY="$HOME/.ssh/id_rsa"
  fi
  WEIGHTS_DIR="${WEIGHTS_DIR:-/var/tmp/models}"
  ABLIT_DIR="${ABLIT_DIR:-$WEIGHTS_DIR/glm52-int4-int8mix-abliterated}"
  HUB_NAME="${HUB_NAME:-glm52-int4-int8mix}"
  KERNELS_DIR="${KERNELS_DIR:-$HOME/glm-triton}"
  NCCL_DIR="${NCCL_DIR:-$WEIGHTS_DIR/hub/nccl-2.30.4}"
  IMAGE="${IMAGE:-vllm-node-tf5-glm52-b12x:probe-modded}"
  GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k}"
  NAME="${NAME:-vllm_qt200k}"
  PORT="${PORT:-8210}"
  MASTER_PORT="${MASTER_PORT:-29501}"

  # Standing SPEED=1 knobs
  UTIL="${UTIL:-0.86}"
  KV_BYTES="${KV_BYTES:-7008000000}"
  MAX_MODEL_LEN="${MAX_MODEL_LEN:-128000}"
  SPEED="${SPEED:-1}"
  MTP_K="${MTP_K:-4}"
  LAYERING="${LAYERING:-0}"

  # Fabric — auto-detect later if still empty
  NCCL_IB_HCA="${NCCL_IB_HCA:-}"
  NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-}"
  GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-}"
  NCCL_IB_GID_INDEX="${NCCL_IB_GID_INDEX:-3}"
}

# Parse NODES from:
#   NODES="ip0 ip1 ip2 ip3"   (head first)
#   or HEAD + WORKERS
#   or file CLUSTER_HOSTS
normalize_nodes() {
  NODES_ARR=()
  if [ -n "${NODES:-}" ]; then
    # shellcheck disable=SC2206
    NODES_ARR=($NODES)
  elif [ -n "${CLUSTER_HOSTS:-}" ] && [ -f "$CLUSTER_HOSTS" ]; then
    mapfile -t NODES_ARR < <(grep -vE '^\s*(#|$)' "$CLUSTER_HOSTS" | awk '{print $1}')
  elif [ -n "${HEAD:-}" ]; then
    # shellcheck disable=SC2206
    NODES_ARR=($HEAD ${WORKERS:-})
  fi
  if [ "${#NODES_ARR[@]}" -gt 0 ]; then
    HEAD="${NODES_ARR[0]}"
    if [ "${#NODES_ARR[@]}" -gt 1 ]; then
      WORKERS="${NODES_ARR[*]:1}"
    else
      WORKERS="${WORKERS:-}"
    fi
    NODES="${NODES_ARR[*]}"
  fi
}

node_user() {
  # Override in cluster.env: node_user() { echo "spark${1##*.}"; }
  echo "${SSH_USER}"
}

# SSH base options (array-friendly)
SSH_BASE_OPTS=(-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

ssh_cmd() {
  # prints a single-line ssh command suitable for rsync -e
  local key_part=""
  [ -f "${SSH_KEY:-}" ] && key_part="-i $SSH_KEY"
  echo "ssh $key_part -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
}

remote() {
  local ip="$1"; shift
  local key_args=()
  [ -f "${SSH_KEY:-}" ] && key_args=(-i "$SSH_KEY")
  ssh "${key_args[@]}" "${SSH_BASE_OPTS[@]}" "$(node_user "$ip")@$ip" "$@"
}

remote_copy() {
  local src="$1" dest="$2"
  local key_args=()
  [ -f "${SSH_KEY:-}" ] && key_args=(-i "$SSH_KEY")
  scp -q "${key_args[@]}" "${SSH_BASE_OPTS[@]}" "$src" "$dest"
}

rsync_ssh() {
  rsync -a "$@" -e "$(ssh_cmd)"
}

# Best-effort fabric detect (RoCE HCA + netdev that is UP)
detect_fabric_into_env() {
  if [ -n "$NCCL_IB_HCA" ] && [ -n "$NCCL_SOCKET_IFNAME" ]; then
    GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"
    return 0
  fi
  if command -v ibdev2netdev >/dev/null 2>&1; then
    # Prefer first UP roce device
    local line hca ifn
    while IFS= read -r line; do
      if echo "$line" | grep -q '(Up)'; then
        hca=$(echo "$line" | awk '{print $1}')
        ifn=$(echo "$line" | awk '{print $5}' | tr -d '()')
        if [ -z "$NCCL_IB_HCA" ]; then NCCL_IB_HCA="$hca"; fi
        if [ -z "$NCCL_SOCKET_IFNAME" ]; then NCCL_SOCKET_IFNAME="$ifn"; fi
        break
      fi
    done < <(ibdev2netdev 2>/dev/null || true)
  fi
  GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-${NCCL_SOCKET_IFNAME:-}}"
}

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

init_cluster() {
  load_cluster_env
  apply_cluster_defaults
  normalize_nodes
  detect_fabric_into_env
}
