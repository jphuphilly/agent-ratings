#!/usr/bin/env bash
# Issue/refresh the ratings-dev TLS cert. Run AFTER the A record points at the
# current Gateway IP. Default issuer is STAGING (LE prod limit: 5 certs/week per
# hostname). Prod:  ISSUER=letsencrypt-prod ./scripts/issue-cert.sh
# Metrics: RECORD=1 appends a cert_issue row to results/rebuild.csv
set -euo pipefail

HOST="${HOST:-ratings-dev.theblockchainarcade.io}"
NS="envoy-gateway-system"
ISSUER="${ISSUER:-letsencrypt-staging}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_FILE="$ROOT/platform/cert-manager/certificate-ratings-dev.yaml"

case "$ISSUER" in
  letsencrypt-staging) EXPECT_STAGING=yes ;;
  letsencrypt-prod)    EXPECT_STAGING=no ;;
  *) echo "ERROR: ISSUER must be letsencrypt-staging or letsencrypt-prod (got: $ISSUER)"; exit 1 ;;
esac

issuer_matches() {
  if [ "$EXPECT_STAGING" = yes ]; then grep -q STAGING; else ! grep -q STAGING; fi
}

kubectl get --raw=/readyz >/dev/null || { echo "ERROR: API server unreachable (check ACL / IPv4)"; exit 1; }

GW_IP=$(kubectl get gateway eg -n "$NS" -o jsonpath='{.status.addresses[0].value}')
[ -n "$GW_IP" ] || { echo "ERROR: Gateway eg has no address"; exit 1; }

# DNS precheck via DoH (direct port 53 is unreliable on some networks).
# Failed HTTP-01 validations count against LE rate limits, so never issue on a mismatch.
DNS_IP=$(curl -fsS -m 10 "https://dns.google/resolve?name=${HOST}&type=A" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(a["data"] for a in d.get("Answer",[]) if a.get("type")==1))') \
  || { echo "ERROR: DoH lookup failed"; exit 1; }
if [ "$DNS_IP" != "$GW_IP" ]; then
  echo "ERROR: $HOST resolves to '${DNS_IP:-nothing}', Gateway is $GW_IP"
  echo "Update the A record in the GoDaddy zone for this hostname (TTL 600), wait, re-run."
  exit 1
fi
echo "[${SECONDS}s] DNS OK: $HOST -> $GW_IP. Issuer: $ISSUER"

sed -E "s/name: letsencrypt-(staging|prod)$/name: $ISSUER/" "$CERT_FILE" | kubectl apply -f -

# Poll the Secret's actual issuer, NOT the Ready condition: on an issuer switch,
# Ready is already True from the old cert (race).
for i in $(seq 1 30); do
  ISS=$(kubectl get secret ratings-dev-tls -n "$NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null \
        | base64 -d 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)
  if [ -n "$ISS" ] && echo "$ISS" | issuer_matches; then break; fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Secret not issued by $ISSUER after 300s"
    kubectl get certificate,certificaterequest,order,challenge -n "$NS" || true
    exit 1
  fi
  sleep 10
done
kubectl wait --for=condition=Ready certificate/ratings-dev -n "$NS" --timeout=60s
echo "[${SECONDS}s] Secret: $ISS"

# Verify what Envoy actually serves (connect by IP: no local-resolver lag).
for i in $(seq 1 12); do
  SERVED=$(echo | openssl s_client -connect "$GW_IP:443" -servername "$HOST" 2>/dev/null \
           | openssl x509 -noout -issuer 2>/dev/null || true)
  if [ -n "$SERVED" ] && echo "$SERVED" | issuer_matches; then break; fi
  if [ "$i" -eq 12 ]; then echo "ERROR: Envoy not serving $ISSUER cert after 60s (got: ${SERVED:-nothing})"; exit 1; fi
  sleep 5
done

echo "[${SECONDS}s] DONE. Served: $SERVED"
if [ "${RECORD:-0}" = "1" ]; then
  echo "$(date -I),cert_issue,${SECONDS}" >> "$ROOT/results/rebuild.csv"
  echo "Recorded cert_issue=${SECONDS}s"
fi
exit 0
