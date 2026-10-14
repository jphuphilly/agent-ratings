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
