#!/usr/bin/env bash
# One-time per cluster: deploy the patient, create the contestant login, write its kubeconfig.
# Run with YOUR admin kubeconfig (kind or LKE). Output: ~/.kube/arena-agent.yaml
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${AGENT_KUBECONFIG:-$HOME/.kube/arena-agent.yaml}"

kubectl get --raw /readyz >/dev/null || { echo "Cluster unreachable. Check KUBECONFIG."; exit 1; }
if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != yes ]; then
  echo "Run this with your admin kubeconfig, not the agent one."; exit 1
fi

kubectl apply -f "$DIR/app.yaml" -f "$DIR/rbac.yaml"
kubectl -n arena rollout status deploy/web --timeout=180s

SERVER=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
TOKEN=$(kubectl -n arena create token agent --duration=8h)

mkdir -p "$(dirname "$OUT")"
umask 077
cat > "$OUT" <<KCFG
apiVersion: v1
kind: Config
clusters:
  - name: arena
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
users:
  - name: agent
    user:
      token: $TOKEN
contexts:
  - name: arena
    context:
      cluster: arena
      user: agent
      namespace: arena
current-context: arena
KCFG

echo
echo "Wrote $OUT (token valid 8h; re-run setup.sh to refresh). Permission check:"
ok=1
expect() { got=$(KUBECONFIG="$OUT" kubectl auth can-i "$@" 2>/dev/null || true); printf '  %-40s %s\n' "can-i $*" "$got"; }
expect get pods -n arena;          [ "$got" = yes ] || ok=0
expect patch deployments -n arena; [ "$got" = yes ] || ok=0
expect get secrets -n arena;       [ "$got" = no ]  || ok=0
expect get pods -n kube-system;    [ "$got" = no ]  || ok=0
expect create deployments -n arena; [ "$got" = no ] || ok=0
if [ "$ok" != 1 ]; then echo "RBAC NOT AS EXPECTED"; exit 1; fi
echo "RBAC OK: agent can fix arena, nothing else."
"$DIR/check.sh" && echo "Baseline healthy. Next: ./arena/run.sh 01-bad-image <contestant-name>"
