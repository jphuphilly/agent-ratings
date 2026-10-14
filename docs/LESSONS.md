# Lessons (write-up material)

- **A hang is not a failure.** An unauthenticated linode-cli opened an interactive wizard inside a
  pipe; `pipefail` can't catch a hang. Fix: an auth preflight, plus `</dev/null` on CLI calls.
- **Checks must fail on empty input.** A comparison against an empty variable printed "different";
  a `grep || echo ok` printed success when kubectl itself failed.
- **Gate destructive steps with `&&`, not comments.** A pasted block deleted a working key because
  "only after step 3 passes" was a comment.
- **Bound every probe.** A "60s" TLS probe loop took 266s because individual probes hung.
  With 10s timeouts, the real gap from cert issued to cert served is ~30-40s.
- **Issuance != serving.** cert_secret (~31-34s) and cert_served (~62-74s) are measured separately.
- **Read DNS flags, not just answers.** "Authoritative" queries from the workstation came back
  `ra` without `aa`, and an unused test IP (192.0.2.1) answered too: the local resolver was
  intercepting all port-53 traffic and caching NXDOMAIN. Moving the check into the cluster
  (+norec, require `aa`) measured GoDaddy's real publish time: ~11s.
- **Public resolvers negative-cache too.** Querying a name before it's published makes the wait longer.
- **Inspect bytes, don't guess encodings.** The LKE kubeconfig output was already-decoded YAML with a
  leading newline (`od -c`).
- **Dangling DNS.** Teardown deletes the A record, so it never points at a recycled IP.
- **GitOps: self-heal is instant, Git sync is polled.** Manual scale 2->5 was reverted in <=1s
  (1-second resolution). Push-to-cluster took 178s and 155s: bounded by Argo's ~3m reconciliation
  poll, not pipeline speed. Proof is `status.sync.revision == git rev-parse HEAD`, not replica count.
- **Argo "Healthy" doesn't check HTTPRoute.** No built-in health check for it; `curl --resolve` -> 200
  stays the real end-to-end test.
- **`git commit -am` sweeps script-written files.** RECORD=1 appends to results/rebuild.csv, which
  landed in an unrelated proof commit. Commit by path.
