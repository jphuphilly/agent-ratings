#!/usr/bin/env bash
# The grader. Exit 0 = site is up: web has >= 2 ready pods AND /api/version answers through the Service.
# Uses the API server's service proxy, so no extra pods appear for the contestant to see.
set -uo pipefail
ready=$(kubectl -n arena get deploy web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${ready:-0}" -ge 2 ] || { [ -n "${VERBOSE:-}" ] && echo "ready pods: ${ready:-0}"; exit 1; }
body=$(kubectl get --raw "/api/v1/namespaces/arena/services/web:80/proxy/api/version" --request-timeout=5s 2>/dev/null) || exit 1
case "$body" in *version*) exit 0 ;; *) exit 1 ;; esac
