# Backlog

- [x] GitOps bootstrap: Argo CD owns `apps/` (verify on next rebuild)
- [ ] GitOps: Argo CD owns `platform/` too
- [ ] run_id column in results CSVs (timestamp from create-cluster, passed through)
- [ ] Envoy proxy: 2 replicas + PodDisruptionBudget (currently 1; externalTrafficPolicy Local)
- [ ] Credential inventory: list every key/token, map it to its user, revoke unused
- [ ] Benchmark script (n=3) against the final GitOps bootstrap path
- [ ] Secret scanning in CI (gitleaks) -- repo is public
- [ ] CI/CD + Renovate, security hardening, observability, write-up
