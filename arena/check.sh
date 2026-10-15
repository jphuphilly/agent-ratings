#!/usr/bin/env bash
# The grader. Exit 0 = site is up: web has >= 2 ready pods AND /api/version answers through the Service.
# Uses the API server's service proxy, so no extra pods appear for the contestant to see.
# Run it with the ADMIN kubeconfig (tab 1). The agent login is not allowed to use the service proxy,
# so from tab 2 it always fails at step 2. VERBOSE=1 prints which step failed.
set -uo pipefail
say() { [ -n "${VERBOSE:-}" ] && echo "check: $*"; return 0; }
ready=$(kubectl -n arena get deploy web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${ready:-0}" -ge 2 ] || { say "FAIL step 1: ready pods ${ready:-0}, need 2"; exit 1; }
say "ok   step 1: ready pods $ready"
if ! body=$(kubectl get --raw "/api/v1/namespaces/arena/services/web:80/proxy/api/version" --request-timeout=5s 2>&1); then
  say "FAIL step 2: /api/version via Service: $body"; exit 1
fi
case "$body" in
  *version*) say "ok   step 2: /api/version -> $body"; exit 0 ;;
  *) say "FAIL step 2: unexpected body: $body"; exit 1 ;;
esac
