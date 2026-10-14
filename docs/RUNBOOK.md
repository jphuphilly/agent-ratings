# Runbook: rebuild, verify, teardown

## Before each session
- `source ~/.config/agent-ratings/env` (Linode token, tfstate bucket keys, GoDaddy PAT; not in repo)
- Your public IP must be in `api_allowed_cidrs` (`infra/envs/dev/terraform.tfvars`, gitignored).
  `create-cluster.sh` fails after 2 minutes and prints your IP next to the allowed list if not.

## Rebuild (run one command at a time)
```bash
RECORD=1 ./scripts/create-cluster.sh
export KUBECONFIG=~/.kube/ratings-dev.yaml          # per shell
RECORD=1 ./scripts/install-platform.sh              # also sets the DNS A record via GoDaddy API
RECORD=1 ISSUER=letsencrypt-staging ./scripts/issue-cert.sh
RECORD=1 ./scripts/install-argocd.sh               # Argo CD then deploys everything in apps/
```

## Verify (before teardown)
```bash
GW_IP=$(kubectl -n envoy-gateway-system get gateway eg -o jsonpath='{.status.addresses[0].value}')
curl -k -m 10 --resolve ratings-dev.theblockchainarcade.io:443:$GW_IP -s -o /dev/null -w '%{http_code}\n' https://ratings-dev.theblockchainarcade.io   # 200
P=$(kubectl get pods -n default -o name) && { echo "$P" | grep dnsprobe || echo "probe cleaned up"; }
```

## Teardown
`RECORD=1 ./scripts/teardown.sh`: destroys the cluster and deletes the DNS record. Idempotent.
If anything fails after create-cluster, still run teardown.

## Metrics (`results/*.csv`, recorded with RECORD=1)
| Metric | Measures |
|---|---|
| cluster_apply | terraform apply |
| cluster_ready | apply start -> all nodes Ready (the stable number to quote) |
| platform_install | Envoy Gateway + cert-manager + issuers |
| argocd_install | Argo CD install -> Application 'apps' Synced/Healthy |
| dns_wait | in-cluster probe ready -> authoritative NS serves the Gateway IP |
| cert_secret | Certificate applied -> Secret signed by the expected issuer |
| cert_served | ... -> Envoy serves that cert on 443 |

## Gotchas
- The workstation's DNS is proxied (ChromeOS resolver at 100.115.92.193) and caches NXDOMAIN.
  Never verify with local `dig` or by name: use `--resolve`. DNS checks run from inside the cluster.
- `ISSUER` takes the full name (`letsencrypt-staging` / `letsencrypt-prod`). Let's Encrypt prod
  allows 5 certs/week, so staging is the default.
