#!/usr/bin/env bash
# One round: reset to healthy -> break -> confirm it's down -> start clock -> grade every 15s.
# Usage: ./arena/run.sh <scenario> <contestant>    e.g. ./arena/run.sh 01-bad-image jake
# RECORD=1 appends the result to results/arena.csv. TIMEOUT defaults to 900s (15 min).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/arena"
SCEN="${1:?usage: run.sh <scenario> <contestant>}"
WHO="${2:?usage: run.sh <scenario> <contestant>}"
SDIR="$DIR/scenarios/$SCEN"
TIMEOUT="${TIMEOUT:-900}"
AGENT_CFG="${AGENT_KUBECONFIG:-$HOME/.kube/arena-agent.yaml}"
[ -d "$SDIR" ] || { echo "No scenario $SCEN. Have: $(ls "$DIR/scenarios")"; exit 1; }
[ -f "$AGENT_CFG" ] || { echo "Run ./arena/setup.sh first."; exit 1; }
[ "$(kubectl auth can-i '*' '*' --all-namespaces)" = yes ] || { echo "Run with your admin kubeconfig."; exit 1; }

echo "[reset] restoring the healthy app"
kubectl apply -f "$DIR/app.yaml" >/dev/null
kubectl -n arena rollout status deploy/web --timeout=180s >/dev/null
for _ in $(seq 1 12); do "$DIR/check.sh" && break; sleep 5; done
"$DIR/check.sh" || { echo "Baseline is not healthy; fix that before grading anyone."; exit 1; }

echo "[break] $SCEN"
bash "$SDIR/break.sh"
for _ in $(seq 1 24); do "$DIR/check.sh" || break; sleep 5; done
"$DIR/check.sh" && { echo "The break did not take the site down. Scenario is broken, not graded."; exit 1; }
echo "[break] confirmed: site is down"

cat <<MSG

=============================== GIVE THIS TO THE CONTESTANT ===============================
$(cat "$SDIR/task.md")

Access: export KUBECONFIG=$AGENT_CFG   (namespace arena only)
============================================================================================
Clock is running. Grading every 15s for up to ${TIMEOUT}s. Ctrl-C to abandon (not recorded).
MSG

T0=$(date +%s)
result=timeout
while [ $(( $(date +%s) - T0 )) -lt "$TIMEOUT" ]; do
  if "$DIR/check.sh"; then result=pass; break; fi
  sleep 15
done
SECS=$(( $(date +%s) - T0 ))
echo
echo "RESULT: $WHO on $SCEN -> $result after ${SECS}s (15s grading resolution)"

if [ "${RECORD:-0}" = 1 ]; then
  CSV="$ROOT/results/arena.csv"
  [ -f "$CSV" ] || echo "date,scenario,contestant,result,seconds" > "$CSV"
  echo "$(date -I),$SCEN,$WHO,$result,$SECS" >> "$CSV"
  echo "Recorded in results/arena.csv"
fi
