# Backlog

- [x] ratings-api v0: FastAPI + own Helm chart + GHCR image via GitHub Actions, deployed by Argo
  (app-of-apps). Verified 2026-10-14: deployed 0.1.0, released 0.1.1 (107s), rolled back by revert (168s)
- [x] GitOps bootstrap: Argo CD owns `apps/`. Verified 2026-10-14: Synced/Healthy, self-heal <=1s,
  push->sync 155-178s, revision matched HEAD
- [ ] GitOps: Argo CD owns `platform/` too. Plan first: Argo would then manage cert-manager/Gateway that
  apps depend on (sync waves / app-of-apps ordering, CRDs before CRs)
- [ ] run_id column in results CSVs (timestamp from create-cluster, passed through)
- [ ] Envoy proxy: 2 replicas + PodDisruptionBudget (currently 1; externalTrafficPolicy Local)
- [ ] Credential inventory: list every key/token, map it to its user, revoke unused
- [ ] Benchmark script (n=3) against the final GitOps bootstrap path
- [x] Secret scanning in CI: gitleaks (full history, default rules + IPv4 rule) and an IP check on new
  commit messages, on every push and PR
- [x] Observability: kube-prometheus-stack + ratings-api SLOs (availability + latency, burn-rate alerts),
  Grafana dashboard, fault-injection drill. Verified 2026-10-14: fast burn fired ~686s after a 20% fault
  push, cleared 349s after revert; slow burn fired after recovery as expected
- [ ] Grafana admin password from a generated Secret (chart default is publicly known; UI is port-forward only)
- [ ] Alertmanager receiver (alerts currently visible only in Prometheus/Alertmanager UIs)
- [ ] CI/CD + Renovate, security hardening, write-up
- [ ] Argo CD webhook from GitHub (needs argocd-server exposed with auth): sync in seconds, not ~3m poll
- [ ] dns_wait: measure from when the A record is written, not from when the probe starts
- [ ] Release automation: CI opens the values.yaml bump PR after pushing an image (removes the manual edit)
- [ ] SLO alerts: `runbook_url` annotations explaining each alert, incl. that slow burn trails recovery.
  Written (docs/ALERTS.md, chart 0.2.1); tick after the annotations are seen in Prometheus on a live cluster
- [ ] Arena v0 (`arena/`): scenario 01 bad image, auto-grader, restricted agent login. Run human baseline
  (jake), then one AI agent. v1: agent in a container holding only the agent kubeconfig; more scenarios; cost tracking
- [ ] Latency SLO drill (inject delay, not just 5xx): only availability has been proven to fire
- [ ] cert_secret jumped to 54s on one run (31-34s before): repeat to see if it's Let's Encrypt staging variance
