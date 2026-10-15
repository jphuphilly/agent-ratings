#!/usr/bin/env bash
# Someone deployed a tag CI never published. With Recreate, old pods die first, new ones can't pull.
# Real-world version: values.yaml bumped before the release tag finished building.
# Tag must never exist in GHCR; if you ever publish 0.2.0-hotfix, change this.
set -euo pipefail
kubectl -n arena set image deploy/web api=ghcr.io/jphuphilly/agent-ratings/ratings-api:0.2.0-hotfix >/dev/null
