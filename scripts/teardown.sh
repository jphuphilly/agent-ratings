#!/usr/bin/env bash
# Full teardown: in-cluster cleanup -> terraform destroy -> verify zero billable leftovers
# via the Linode API (not Terraform state). Always records the result; exits 1 unless all 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/infra/envs/dev"
CSV="$ROOT/results/teardown.csv"
: "${LINODE_CLI_TOKEN:?source ~/.config/agent-ratings.env first}"

# 1. Remove things the cluster created outside Terraform (LBs, PVCs). Has its own confirm prompt.
"$ROOT/scripts/pre-destroy.sh"

# 2. Destroy (timed separately so prompt think-time isn't in the number)
T0=$(date +%s)
terraform -chdir="$TF_DIR" destroy -auto-approve
DESTROY_SECS=$(( $(date +%s) - T0 ))

# 3. Count leftovers. A failed API call must FAIL, never read as 0.
count() {
  local out
  out=$(linode-cli "$@" --text --no-headers) || { echo "linode-cli $* failed" >&2; exit 1; }
  printf '%s' "$out" | grep -c . || true
}
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
