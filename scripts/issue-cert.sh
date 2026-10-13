#!/usr/bin/env bash
# Issue/refresh the ratings-dev TLS cert. Run AFTER the A record points at the
# current Gateway IP. Default issuer is STAGING (LE prod limit: 5 certs/week per
# hostname). Prod:  ISSUER=letsencrypt-prod ./scripts/issue-cert.sh
# Metrics: RECORD=1 appends cert_secret, cert_served, dns_wait rows to results/rebuild.csv
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

# Failed HTTP-01 validations count against LE rate limits, so never issue on a mismatch.
# DNS precheck from INSIDE the cluster. This workstation's port 53 is intercepted
# (a proxy answers every query and caches NXDOMAIN), and public resolvers
# negative-cache too. A pod on Linode asks the zone's authoritative NS directly
# (+norec, require the 'aa' flag): nothing cached, same vantage point as Let's Encrypt.
PROBE=dnsprobe-$$
kubectl -n default run "$PROBE" --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never --command -- sleep 900 >/dev/null
trap 'kubectl -n default delete pod "$PROBE" --wait=false >/dev/null 2>&1 || true' EXIT
kubectl -n default wait pod/"$PROBE" --for=condition=Ready --timeout=120s >/dev/null
pdig() { kubectl -n default exec "$PROBE" -- dig "$@"; }
ZONE_NS=$(pdig +short NS "${HOST#*.}" | head -1)
[ -n "$ZONE_NS" ] || { echo "ERROR: no NS found for ${HOST#*.} from inside the cluster"; exit 1; }
SECONDS=0   # dns_wait starts once the probe is ready (excludes image pull)
DNS_IP=""; STATE=""
for i in $(seq 1 60); do
  OUT=$(pdig +norec +time=5 +tries=1 A "$HOST" @"$ZONE_NS" 2>&1 || true)
  if echo "$OUT" | grep -q 'flags:[a-z ]* aa'; then
    DNS_IP=$(echo "$OUT" | awk '$4=="A"{print $5}' | sort | tr '\n' ' ' | sed 's/ $//')
    STATE="${DNS_IP:-not published yet}"
  else
    DNS_IP=""
    STATE="no authoritative answer ($(echo "$OUT" | grep -oE 'timed out|status: [A-Z]+' | head -1))"
  fi
  [ "$DNS_IP" = "$GW_IP" ] && break
  echo "[${SECONDS}s] DNS $i: $STATE from $ZONE_NS (want $GW_IP)"
  sleep 10
done
[ "$DNS_IP" = "$GW_IP" ] || { echo "ERROR: $ZONE_NS not serving $GW_IP for $HOST after 10m (last: $STATE). Check: ./scripts/set-dns.sh show"; exit 1; }
echo "[${SECONDS}s] DNS OK: $HOST -> $GW_IP. Issuer: $ISSUER"
DNS_WAIT=$SECONDS; SECONDS=0   # cert_issue excludes DNS wait

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
CERT_SECRET=$SECONDS
echo "[${SECONDS}s] Secret: $ISS"

# Verify what Envoy actually serves (connect by IP: no local-resolver lag).
for i in $(seq 1 12); do
  SERVED=$(echo | timeout 10 openssl s_client -connect "$GW_IP:443" -servername "$HOST" 2>/dev/null \
           | openssl x509 -noout -issuer 2>/dev/null || true)
  echo "[${SECONDS}s] probe $i: ${SERVED:-no cert}"
  if [ -n "$SERVED" ] && echo "$SERVED" | issuer_matches; then break; fi
  if [ "$i" -eq 12 ]; then echo "ERROR: Envoy not serving $ISSUER cert after 12 probes (got: ${SERVED:-nothing})"; exit 1; fi
  sleep 5
done

echo "[${SECONDS}s] DONE. Served: $SERVED"
if [ "${RECORD:-0}" = "1" ]; then
  echo "$(date -I),cert_secret,${CERT_SECRET}" >> "$ROOT/results/rebuild.csv"
  echo "$(date -I),cert_served,${SECONDS}" >> "$ROOT/results/rebuild.csv"
  echo "$(date -I),dns_wait,${DNS_WAIT}" >> "$ROOT/results/rebuild.csv"
  echo "Recorded cert_secret=${CERT_SECRET}s cert_served=${SECONDS}s dns_wait=${DNS_WAIT}s"
fi
exit 0
