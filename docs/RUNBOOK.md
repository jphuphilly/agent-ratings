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
kubectl -n argocd get application apps -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'   # Synced/Healthy
```
Argo reports HTTPRoute as Healthy without checking it, so the `curl --resolve` 200 is the real end-to-end test.

## Teardown
`RECORD=1 ./scripts/teardown.sh`: destroys the cluster and deletes the DNS record. Idempotent.
If anything fails after create-cluster, still run teardown.

## Metrics (`results/*.csv`, recorded with RECORD=1)
| Metric | Measures | Observed (as of 2026-10-14) |
|---|---|---|
| cluster_apply | terraform apply | 102-188s, noisy |
| cluster_ready | apply start -> all nodes Ready (the stable number to quote) | **179-208s (n=5)** |
| platform_install | Envoy Gateway + cert-manager + issuers | 55-113s (range only, noisy) |
| argocd_install | Argo CD install -> Application 'apps' Synced/Healthy | 54s (n=1) |
| dns_wait | in-cluster probe ready -> authoritative NS serves the Gateway IP | 10-11s (n=2 honest runs) |
| cert_secret | Certificate applied -> Secret signed by the expected issuer | 31-34s (n=4) |
| cert_served | ... -> Envoy serves that cert on 443 | 62-78s (n=3 bounded runs) |
| teardown | destroy cluster + delete DNS record | ~40s |

Excluded as measurement artifacts: cert_served 300 (unbounded probe loop) and dns_wait 1
(workstation resolver, not the authoritative server). See LESSONS.md.

Not in the CSVs (measured by hand on 2026-10-14):
- self-heal: manual scale 2->5 reverted to 2 in <=1s (1-second resolution).
- push->cluster sync: 178s and 155s (n=2). Bounded by Argo's ~3m poll, so this is a config value,
  not pipeline speed.

## GitOps (Argo CD owns `apps/`)
- `platform/argocd/apps-application.yaml`: path `apps/`, recurse, automated sync, prune, selfHeal.
  Public repo, so no repo credentials.
- To change an app: edit under `apps/`, **commit by path** (`git commit apps/... -m ...`), push.
  Expect it on the cluster within ~3m.
- Proof of deploy = `kubectl -n argocd get application apps -o jsonpath='{.status.sync.revision}'`
  equals `git rev-parse HEAD`. The replica count alone is not proof.
- Anything deleted from `apps/` is pruned. Any manual `kubectl` change to an Argo-owned object is reverted.
- UI (not exposed): `kubectl -n argocd port-forward svc/argocd-server 8080:443`, user `admin`, password in
  secret `argocd-initial-admin-secret`.

## Gotchas
- The workstation's DNS is proxied (ChromeOS resolver at 100.115.92.193) and caches NXDOMAIN.
  Never verify with local `dig` or by name: use `--resolve`. DNS checks run from inside the cluster.
- `ISSUER` takes the full name (`letsencrypt-staging` / `letsencrypt-prod`). Let's Encrypt prod
  allows 5 certs/week, so staging is the default.
- Scripts append to tracked `results/*.csv` when RECORD=1. Commit by path, never `git commit -am`,
  or those rows end up in unrelated commits.
