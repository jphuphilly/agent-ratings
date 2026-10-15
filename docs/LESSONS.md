# Lessons (write-up material)

- **A hang is not a failure.** An unauthenticated linode-cli opened an interactive wizard inside a
  pipe; `pipefail` can't catch a hang. Fix: an auth preflight, plus `</dev/null` on CLI calls.
- **Checks must fail on empty input.** A comparison against an empty variable printed "different";
  a `grep || echo ok` printed success when kubectl itself failed.
- **Gate destructive steps with `&&`, not comments.** A pasted block deleted a working key because
  "only after step 3 passes" was a comment.
- **Bound every probe.** A "60s" TLS probe loop took 266s because individual probes hung.
  With 10s timeouts, the real gap from cert issued to cert served is ~30-40s.
- **Issuance != serving.** cert_secret (~31-34s) and cert_served (~62-78s) are measured separately.
- **Read DNS flags, not just answers.** "Authoritative" queries from the workstation came back
  `ra` without `aa`, and an unused test IP (192.0.2.1) answered too: the local resolver was
  intercepting all port-53 traffic and caching NXDOMAIN. Moving the check into the cluster
  (+norec, require `aa`) measured GoDaddy's real publish time: ~11s.
- **Public resolvers negative-cache too.** Querying a name before it's published makes the wait longer.
- **Inspect bytes, don't guess encodings.** The LKE kubeconfig output was already-decoded YAML with a
  leading newline (`od -c`).
- **Dangling DNS.** Teardown deletes the A record, so it never points at a recycled IP.
- **GitOps: self-heal is event-driven, Git sync is polled.** A manual scale 2->5 was reverted in <=1s.
  Pushes reached the cluster in 178s and 155s: just under Argo's 180s reconciliation poll. That's a
  config value, not pipeline speed. A GitHub webhook would cut it to seconds.
- **Prove the revision, not the symptom.** "Replicas went to 3" could have other causes;
  `status.sync.revision == git rev-parse HEAD` proves the cluster runs the commit just pushed.
- **"Healthy" can be hollow.** Argo has no built-in health check for Gateway API HTTPRoute, so it reports
  Healthy without checking. The end-to-end `curl --resolve` -> 200 remains the real test.
- **`git commit -am` sweeps in side effects.** RECORD=1 appends to the tracked results CSV, and those rows
  landed in an unrelated GitOps proof commit. Commit by path.
- **Ranges move as n grows.** cluster_ready was quoted as 181-208s at n=4; run 5 came in at 179s.
  Quote a range with its n, and update it after every run.
- **A tag builds only what exists at its commit.** The first `ratings-api-v0.1.0` tag was created before
  pulling the merge, so it pointed at a commit without the workflow file: GitHub had nothing to run and no
  image was built. Fix: delete and re-push the tag on the merge commit. Rule: `git log -1` before tagging.
- **Release and rollback are both commits.** 0.1.0 -> 0.1.1 went live in 107s by changing one line in
  values.yaml; `git revert` brought 0.1.0 back in 168s. No kubectl, no helm upgrade by hand.
- **A wait timer measures from when it starts.** dns_wait read 0s because install-platform had been re-run,
  so the record was already published before the probe began. The number is true but measures nothing.
  Measuring from the moment the record is written would fix it.
- **"Network is unreachable" can mean "IPv6 only".** A Helm chart pull from Docker Hub failed by dialing an
  IPv6 address the workstation can't route. Intermittent; a re-run succeeded. Read the address in the error
  before debugging the network.
- **"No manual steps" has to include teardown.** pre-destroy.sh stops for a y/N confirmation. Kept as the
  interactive default (it deletes things); `ASSUME_YES=1` now skips it for unattended runs.
- **Two windows, two jobs.** After the SLO drill was reverted, the 1h burn rate still read 14.7 (above 14.4),
  yet the fast alert cleared because the 5m window had dropped to 0. The long window prevents false alarms from
  short spikes; the short window stops a fixed incident from paging.
- **The long window sets detection time.** At 20% errors the fast alert fired ~11.5 min after the push:
  ~3 min Argo poll, then the 1h ratio needed ~7 min of faults to outweigh 12 min of clean traffic, plus the
  2m `for`. With a full clean hour behind it, 20% errors would take ~24 min; 100% errors ~4 min.
- **Slow-burn alerts trail recovery.** The 6x alert went pending first (lower threshold) but needs 15m, so it
  fired ~1.5 min after the service was healthy. It resolves as its 30m window drains. Expected, not a bug.
- **A restart resets the short window.** The 5m error ratio hit ~0.21 within ~4 min, not a slow ramp: the
  rollout replaced the pods, and the new pods' counters only ever saw faulted traffic.
- **Time incidents from server timestamps.** Screenshot clocks suggested the alert took 6 min; GitHub's push
  time and Prometheus `activeAt` showed ~11.5 min. Use the systems' own timestamps, not when someone looked.
- **A budget needs history.** "0.0% error budget remaining" after 13 minutes of 20% errors is true only
  because a fresh Prometheus had ~35 minutes of data. Report a budget with the window it was computed over.
