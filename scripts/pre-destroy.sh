#!/usr/bin/env bash
set -euo pipefail
echo "LoadBalancer services:"; kubectl get svc -A --field-selector spec.type=LoadBalancer || true
echo "PVCs:"; kubectl get pvc -A || true
read -rp "Delete all LoadBalancer services and PVCs? [y/N] " ans
[[ "$ans" == "y" ]] || exit 1
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
  while read -r ns name; do kubectl delete svc -n "$ns" "$name"; done
kubectl delete pvc -A --all --wait=true
echo "Check Cloud Manager for leftover NodeBalancers/Volumes, then run terraform destroy."
