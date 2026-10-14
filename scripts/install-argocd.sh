#!/usr/bin/env bash
# Installs Argo CD, then the "apps" Application -- from here on Argo deploys apps/.
# Separate from install-platform.sh so platform_install timings stay comparable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/platform/versions.env"
: "${ARGOCD_VERSION:?ARGOCD_VERSION not set in versions.env}"

START=$(date +%s)
log() { echo "[$(( $(date +%s) - START ))s] $*"; }
kubectl get --raw /readyz >/dev/null || { echo "Cluster unreachable. Check KUBECONFIG / API ACL."; exit 1; }

log "Argo CD chart $ARGOCD_VERSION"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_VERSION" \
  -n argocd --create-namespace -f "$ROOT/platform/argocd/values.yaml" \
  --wait --timeout 10m

log "Applying Application 'apps' (path apps/)"
kubectl apply -f "$ROOT/platform/argocd/apps-application.yaml"

S=""
for _ in $(seq 1 60); do
  S=$(kubectl -n argocd get application apps \
      -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  [ "$S" = "Synced/Healthy" ] && break
  sleep 5
done
if [ "$S" != "Synced/Healthy" ]; then
  echo "ERROR: apps not Synced/Healthy after 5m (got: ${S:-nothing})"
  kubectl -n argocd get application apps -o yaml | sed -n '/^status:/,$p' | head -40
  exit 1
fi

ELAPSED=$(( $(date +%s) - START ))
log "DONE. apps: $S  argocd_install: ${ELAPSED}s"
[ "${RECORD:-0}" = 1 ] && echo "$(date -I),argocd_install,${ELAPSED}" >> "$ROOT/results/rebuild.csv"
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:443   (user: admin)"
echo "    password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
exit 0
