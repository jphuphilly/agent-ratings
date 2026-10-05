#!/usr/bin/env bash
# Installs in-cluster platform: Envoy Gateway -> Gateway -> cert-manager -> ClusterIssuer.
# Idempotent: safe to re-run. Versions come ONLY from platform/versions.env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/platform/versions.env"
: "${EG_VERSION:?EG_VERSION not set in versions.env}"
: "${CM_VERSION:?CM_VERSION not set in versions.env}"

START=$(date +%s)
log() { echo "[$(( $(date +%s) - START ))s] $*"; }

# Fail fast if the cluster isn't reachable (wrong KUBECONFIG, IP ACL, cluster gone)
kubectl get --raw /readyz >/dev/null || { echo "Cluster unreachable. Check KUBECONFIG / API ACL."; exit 1; }

log "Envoy Gateway $EG_VERSION"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$EG_VERSION" -n envoy-gateway-system --create-namespace \
  --wait --timeout 5m
kubectl wait -n envoy-gateway-system deployment/envoy-gateway \
  --for=condition=Available --timeout=5m

log "Applying GatewayClass + Gateway"
kubectl apply -f "$ROOT/platform/gateway/gateway.yaml"
kubectl wait -n envoy-gateway-system gateway/eg \
  --for=condition=Programmed --timeout=5m

log "Waiting for Gateway address"
IP=""
for _ in $(seq 1 30); do
  IP=$(kubectl get gateway eg -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  [ -n "$IP" ] && break
  sleep 10
done
[ -n "$IP" ] || { echo "Gateway never got an address"; exit 1; }

log "cert-manager $CM_VERSION"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "$CM_VERSION" -n cert-manager --create-namespace \
  -f "$ROOT/platform/cert-manager/values.yaml" \
  --wait --timeout 10m

log "Applying ClusterIssuer"
kubectl apply -f "$ROOT/platform/cert-manager/clusterissuer-staging.yaml"
kubectl wait clusterissuer/letsencrypt-staging --for=condition=Ready --timeout=3m

ELAPSED=$(( $(date +%s) - START ))
log "DONE. Gateway IP: $IP  platform_install: ${ELAPSED}s"
echo "$(date -I),platform_install,${ELAPSED}" >> "$ROOT/results/rebuild.csv"
