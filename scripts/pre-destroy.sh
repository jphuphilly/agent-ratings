#!/usr/bin/env bash
set -euo pipefail

lb_services() {
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'
}

has_gateway_api() {
  kubectl api-resources --api-group=gateway.networking.k8s.io -o name | grep -q '^gateways\.'
}

echo "Gateways:"
if has_gateway_api; then kubectl get gateway -A; else echo "  (Gateway API not installed)"; fi
echo "LoadBalancer services:"; lb_services
echo "PVCs:"; kubectl get pvc -A

read -rp "Delete all Gateways, LoadBalancer services and PVCs? [y/N] " ans
[[ "$ans" == "y" ]] || exit 1

# 1. Gateways first, or Envoy Gateway recreates their LoadBalancer Services
if has_gateway_api; then
  echo "Deleting Gateways..."
  kubectl delete gateway --all -A --wait=true
fi

# 2. Any other LoadBalancer Services
lb_services | while read -r ns name; do
  echo "Deleting service $ns/$name"
  kubectl delete svc -n "$ns" "$name" --wait=true
done

# 3. PVCs
kubectl delete pvc --all -A --wait=true

# 4. Wait for NodeBalancers to disappear; refuse to continue if they don't
for i in $(seq 1 30); do
  count=$(linode-cli nodebalancers list --text --no-headers | wc -l)
  if [ "$count" -eq 0 ]; then
    echo "NodeBalancers gone."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: $count NodeBalancer(s) still present after 5 minutes. Do NOT run terraform destroy." >&2
    linode-cli nodebalancers list
    exit 1
  fi
  echo "  $count NodeBalancer(s) remaining, waiting 10s..."
  sleep 10
done

# 5. Volumes are not removed automatically if the StorageClass retains them
echo "Linode Volumes on the account:"
linode-cli volumes list
echo "Delete any that belong to this cluster with: linode-cli volumes delete <ID>"
echo "Safe to run terraform destroy."