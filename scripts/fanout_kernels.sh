#!/usr/bin/env bash
# Install kernels on head (from repo) and rsync to workers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

say "Install kernels locally"
bash "$ROOT/scripts/install_kernels.sh"

normalize_nodes
if [ -z "${WORKERS:-}" ]; then
  warn "no WORKERS/NODES workers — local only"
  exit 0
fi

say "Fanout kernels → $KERNELS_DIR on workers"
for ip in $WORKERS; do
  echo "  → $ip"
  remote "$ip" "mkdir -p $KERNELS_DIR"
  rsync -a -e "$(ssh_cmd)" \
    "$KERNELS_DIR/" "$(node_user "$ip")@$ip:$KERNELS_DIR/" \
    || die "kernel rsync failed → $ip"
  n=$(remote "$ip" "ls $KERNELS_DIR/*.py 2>/dev/null | wc -l" | tr -d ' \r')
  [ "${n:-0}" -ge 10 ] || die "worker $ip has only $n kernel py files"
  ok "$ip ($n files)"
done
echo "OK — kernels on all ranks"
