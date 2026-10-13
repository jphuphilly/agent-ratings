#!/usr/bin/env bash
# Creates the LKE cluster via Terraform, writes kubeconfig, waits for all nodes Ready.
# cluster_apply = terraform apply time; cluster_ready = apply start -> all nodes Ready.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/infra/envs/dev"
KCFG="$HOME/.kube/ratings-dev.yaml"

: "${LINODE_TOKEN:?run: source ~/.config/agent-ratings/env}"
: "${AWS_SECRET_ACCESS_KEY:?run: source ~/.config/agent-ratings/env}"

START=$(date +%s)
terraform -chdir="$TF" apply -auto-approve -input=false
APPLY=$(( $(date +%s) - START ))
echo "[${APPLY}s] terraform apply done"

mkdir -p "$HOME/.kube"
RAW=$(terraform -chdir="$TF" output -raw kubeconfig)
if printf '%s' "$RAW" | grep -q '^apiVersion:'; then
  printf '%s\n' "$RAW" > "$KCFG"            # output already decoded
else
  printf '%s' "$RAW" | base64 -d > "$KCFG"   # output is base64
fi
chmod 600 "$KCFG"
grep -q '^apiVersion' "$KCFG" || { echo "kubeconfig decode failed"; exit 1; }
export KUBECONFIG="$KCFG"

EXPECTED=$(terraform -chdir="$TF" show -json \
  | jq '[.. | objects | select(.type? == "linode_lke_cluster") | .values.pool[]?.count] | add')
[[ "$EXPECTED" =~ ^[0-9]+$ ]] || { echo "Could not read node count from state (got: $EXPECTED)"; exit 1; }

READY=0
for _ in $(seq 1 60); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l || true)
  [ "${READY:-0}" -ge "$EXPECTED" ] && break
  sleep 10
done
[ "${READY:-0}" -ge "$EXPECTED" ] || { echo "Only ${READY:-0}/$EXPECTED nodes Ready after 10m"; kubectl get nodes || true; exit 1; }
CLUSTER_READY=$(( $(date +%s) - START ))

echo "[${CLUSTER_READY}s] $READY/$EXPECTED nodes Ready"
if [ "${RECORD:-0}" = 1 ]; then
  echo "$(date -I),cluster_apply,${APPLY}" >> "$ROOT/results/rebuild.csv"
  echo "$(date -I),cluster_ready,${CLUSTER_READY}" >> "$ROOT/results/rebuild.csv"
fi
echo "NEXT: export KUBECONFIG=$KCFG && RECORD=1 ./scripts/install-platform.sh"
