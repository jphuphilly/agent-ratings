# Alert runbooks: ratings-api SLOs

Each SLO alert in `charts/ratings-api/templates/prometheusrule.yaml` links here through its `runbook_url`
annotation. Section headings are the exact alert names, so the link anchor is the name in lowercase.
Targets and windows are in RUNBOOK.md, "Observability and SLOs".

Setup for every check below (one tab; see RUNBOOK.md "Before each session"):
```bash
kubectl -n monitoring port-forward svc/kps-prometheus 9090 >/dev/null 2>&1 &
q() { curl -s localhost:9090/api/v1/query --data-urlencode "query=$1" | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print([x["value"][1] for x in r] or "no data")'; }
```

## RatingsApiErrorBudgetBurnFast
**Severity:** page. **Means:** more than 14.4 x 0.5% = 7.2% of /api requests returned 5xx over both the
last 1h and the last 5m, for 2 minutes. At that rate 2% of a 30-day budget burns per hour.

**Check**
```bash
q 'ratings_api:sli_errors:ratio_rate5m'      # current 5xx share; 0.2 during the drill
q 'ratings_api:sli_errors:ratio_rate1h'
grep faultRate charts/ratings-api/values.yaml   # anything but "0" is an injected fault
kubectl -n ratings get pods                  # restarts, CrashLoopBackOff, not Ready
kubectl -n ratings logs deploy/ratings-api --tail=50
git log --oneline -5 -- charts/ratings-api services   # what changed recently
```

**Act**
- Injected fault (`faultRate` not "0") or a bad release: `git revert <commit>`, push, let Argo sync (~3m poll).
  Rollback by revert measured 168s; the drill alert cleared 349s after the revert was pushed.
- Pods unhealthy with no recent change: describe the pod (`kubectl -n ratings describe pod <name>`) and
  check node pressure (`kubectl get nodes`).

**Clears when** the 5m ratio drops below 7.2%. The 1h ratio can stay high for up to an hour after recovery
(it stayed at 14.7x in the drill); that is expected and does not keep this alert firing.

## RatingsApiErrorBudgetBurnSlow
**Severity:** ticket. **Means:** more than 6 x 0.5% = 3% of /api requests returned 5xx over both the
last 6h and the last 30m, for 15 minutes.

**It can fire after the service has already recovered.** The 30m window still contains the incident for up
to 30 minutes, and the 15m `for` delays it further. In the 2026-10-14 drill it fired about 7 minutes after the
revert was pushed, when the fast-burn alert had already cleared. So check the current state before acting:
```bash
q 'ratings_api:sli_errors:ratio_rate5m'      # 0 = already recovered; this alert is trailing
q 'ratings_api:sli_errors:ratio_rate30m'     # falls below 0.03 as the incident ages out
```

**Act**
- 5m ratio is 0 and a fast-burn incident just ended: no action. It resolves as the 30m window drains.
  Note it in the incident record.
- 5m ratio is above 0 with no fast-burn alert: a low, steady error rate. Use the checks under
  RatingsApiErrorBudgetBurnFast to find the cause, then fix or revert in a normal ticket.

**Clears when** the 30m ratio drops below 3%.

## RatingsApiLatencyBudgetBurnFast
**Severity:** page. **Means:** more than 14.4 x 1% = 14.4% of /api requests took 250ms or longer, over
both the last 1h and the last 5m, for 2 minutes. Not yet proven in a drill (BACKLOG.md).

**Check**
```bash
q 'ratings_api:sli_slow:ratio_rate5m'        # share of slow requests now
q 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="ratings-api",route=~"/api/.*"}[5m])))'   # p99 in seconds
kubectl -n ratings top pods                  # CPU near the node's spare capacity? (requests are 25m)
kubectl -n ratings get pods                  # restarts or OOMKilled (memory limit 128Mi)
git log --oneline -5 -- charts/ratings-api services
```

**Act**
- Slow after a release: revert it, as for the error-budget alert.
- CPU-starved or OOMKilled: raise `resources` in `charts/ratings-api/values.yaml` or `replicaCount`, commit,
  push.

**Clears when** the 5m slow share drops below 14.4%.

## RatingsApiNoTraffic
**Severity:** ticket. **Means:** no /api requests seen for 10 minutes, or the request-rate series is missing.
The SLO alerts above cannot fire without traffic, so this is the alert that tells you they are blind.

**Check**
```bash
kubectl -n ratings get pods -l app.kubernetes.io/name=ratings-api-loadgen   # load generator running?
kubectl -n ratings logs deploy/ratings-api-loadgen --tail=20
curl -s 'localhost:9090/api/v1/targets?state=active' | python3 -c 'import sys,json; print([t["health"] for t in json.load(sys.stdin)["data"]["activeTargets"] if t["labels"].get("job")=="ratings-api"])'   # expect ['up', 'up']
kubectl -n argocd get applications           # ratings-api Synced/Healthy?
```

**Act**
- Loadgen down: check `loadgen.enabled` in values.yaml and the pod's events.
- Targets missing or down: the ServiceMonitor or the API pods are the problem, not traffic. Check
  `kubectl -n ratings get servicemonitor` and the pods.
- Fresh cluster: expected for the first ~10 minutes while monitoring installs. Wait.

**Clears when** the 5m request rate is above 0 again.
