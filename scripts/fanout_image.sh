#!/usr/bin/env bash
# Ensure standing image exists on every node.
# Prefer parallel docker pull on workers; fall back to docker save | ssh load.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

GHCR="${GHCR_IMAGE:-ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k}"
LOCAL="${IMAGE:-vllm-node-tf5-glm52-b12x:probe-modded}"

say "Ensure image on head"
bash "$ROOT/scripts/pull_image.sh"

normalize_nodes
if [ -z "${WORKERS:-}" ]; then
  warn "no workers — image local only"
  exit 0
fi

tag_local_on_remote() {
  local ip="$1"
  remote "$ip" "docker tag '$GHCR' '$LOCAL' 2>/dev/null; docker tag '$GHCR' 'vllm-node-tf5-glm52-b12x:speed1-c1-30-128k' 2>/dev/null; docker image inspect '$LOCAL' >/dev/null"
}

say "Fanout image to workers (pull preferred)"
FAILED=()
for ip in $WORKERS; do
  echo "  → $ip pull $GHCR"
  if remote "$ip" "docker pull '$GHCR' && docker tag '$GHCR' '$LOCAL'"; then
    ok "pulled on $ip"
  else
    warn "pull failed on $ip — will try save|load"
    FAILED+=("$ip")
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  say "docker save | load fallback for: ${FAILED[*]}"
  TMP_TAR="${TMPDIR:-/tmp}/vllm-glm52-speed1-$$.tar"
  # stream without full local tar if possible
  for ip in "${FAILED[@]}"; do
    echo "  → $ip load via pipe"
    if docker save "$LOCAL" | remote "$ip" "docker load"; then
      remote "$ip" "docker tag '$LOCAL' '$GHCR' 2>/dev/null; true"
      tag_local_on_remote "$ip" || die "image not usable on $ip after load"
      ok "loaded on $ip"
    else
      # second try: save to file then scp (more reliable on flaky pipes)
      docker save -o "$TMP_TAR" "$LOCAL"
      remote "$ip" "mkdir -p /tmp"
      rsync -a -e "$(ssh_cmd)" \
        "$TMP_TAR" "$(node_user "$ip")@$ip:/tmp/vllm-glm52-speed1.tar" \
        || die "image rsync failed → $ip"
      remote "$ip" "docker load -i /tmp/vllm-glm52-speed1.tar && rm -f /tmp/vllm-glm52-speed1.tar && docker tag '$LOCAL' '$LOCAL'" \
        || die "docker load failed on $ip"
      ok "loaded on $ip (scp path)"
    fi
  done
  rm -f "${TMP_TAR:-}"
fi

# Final inspect
for ip in $WORKERS; do
  remote "$ip" "docker image inspect '$LOCAL' >/dev/null" || die "missing $LOCAL on $ip"
done
echo "OK — image on all ranks ($LOCAL)"
