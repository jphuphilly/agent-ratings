# Backlog

- [x] GitOps bootstrap: Argo CD owns `apps/`. Verified 2026-10-14: Synced/Healthy, self-heal <=1s,
  push->sync 155-178s, revision matched HEAD
- [ ] GitOps: Argo CD owns `platform/` too. Plan first: Argo would then manage cert-manager/Gateway that
  apps depend on (sync waves / app-of-apps ordering, CRDs before CRs)
- [ ] run_id column in results CSVs (timestamp from create-cluster, passed through)
- [ ] Envoy proxy: 2 replicas + PodDisruptionBudget (currently 1; externalTrafficPolicy Local)
- [ ] Credential inventory: list every key/token, map it to its user, revoke unused
- [ ] Benchmark script (n=3) against the final GitOps bootstrap path
- [ ] Secret scanning in CI (gitleaks) -- repo is public
- [ ] CI/CD + Renovate, security hardening, observability, write-up
- [ ] Argo CD webhook from GitHub (needs argocd-server exposed with auth): sync in seconds, not ~3m poll
