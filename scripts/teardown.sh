#!/usr/bin/env bash
# Full teardown: in-cluster cleanup -> terraform destroy -> verify zero billable leftovers
# via the Linode API (not Terraform state). Always records the result; exits 1 unless all 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/infra/envs/dev"
CSV="$ROOT/results/teardown.csv"
: "${LINODE_TOKEN:?run: source ~/.config/agent-ratings/env}"
: "${AWS_SECRET_ACCESS_KEY:?run: source ~/.config/agent-ratings/env}"

# 0. Preflight. An unauthenticated linode-cli opens an interactive wizard and
#    HANGS instead of failing -- so check auth explicitly, with stdin closed.
linode-cli profile view --json </dev/null >/dev/null 2>&1 \
  || { echo "linode-cli not authenticated (run: linode-cli configure --token)"; exit 2; }

count() {
  local out
  out=$(linode-cli "$@" --text --no-headers </dev/null) || { echo "linode-cli $* failed" >&2; exit 1; }
  printf '%s' "$out" | grep -c . || true
}

# Idempotent: no cluster -> verify nothing is billing, exit 0, no CSV row.
CL0=$(count lke clusters-list)
if [ "$CL0" = 0 ]; then
  NB0=$(count nodebalancers list); VOL0=$(count volumes list); LN0=$(count linodes list)
  if [ "$NB0$VOL0$LN0" = "000" ]; then
    echo "Already clean: no cluster, no orphans. Nothing to do."; exit 0
  fi
  echo "No cluster, but orphans exist: NB=$NB0 VOL=$VOL0 LN=$LN0. Check the Linode console."; exit 1
fi

# 1. Remove things the cluster created outside Terraform (LBs, PVCs). Has its own confirm prompt.
"$ROOT/scripts/pre-destroy.sh"

# 2. Destroy (timed separately so prompt think-time isn't in the number)
T0=$(date +%s)
terraform -chdir="$TF_DIR" destroy -auto-approve
DESTROY_SECS=$(( $(date +%s) - T0 ))

# 3. Count leftovers. A failed API call must FAIL, never read as 0.
NB=$(count nodebalancers list)
VOL=$(count volumes list)
CL=$(count lke clusters-list)
LN=$(count linodes list)
STATE_OUT=$(terraform -chdir="$TF_DIR" state list)
ST=$(printf '%s' "$STATE_OUT" | grep -c . || true)

echo "$(date -I),$NB,$VOL,$CL,$LN,$ST,$DESTROY_SECS" >> "$CSV"
echo "NodeBalancers=$NB Volumes=$VOL Clusters=$CL Linodes=$LN StateResources=$ST destroy=${DESTROY_SECS}s"

if [ "$NB$VOL$CL$LN$ST" = "00000" ]; then
  echo "CLEAN: nothing billing."
else
  echo "LEFTOVERS: check the Linode console now. Billing may continue."
  exit 1
fi
