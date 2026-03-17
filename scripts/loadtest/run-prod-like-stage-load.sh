#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_GATEWAY_SERVICE_IP="$(kubectl -n demo-stage get svc api-gateway -o jsonpath='{.spec.clusterIP}')"
PROMETHEUS_SERVICE_IP="$(kubectl -n monitoring get svc kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')"

TARGET_URL="${TARGET_URL:-http://${API_GATEWAY_SERVICE_IP}:8080}"
LUA_SCRIPT="${LUA_SCRIPT:-$REPO_ROOT/scripts/loadtest/gateway-mixed-stage.lua}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-$REPO_ROOT/.loadtest/stage-prod-like-$(date +%Y%m%d-%H%M%S)}"
PROM_URL="${PROM_URL:-http://${PROMETHEUS_SERVICE_IP}:9090/api/v1/query}"
PROM_HOST_HEADER="${PROM_HOST_HEADER:-}"

mkdir -p "$ARTIFACT_ROOT"

snapshot_state() {
  local phase_name="$1"
  local snapshot_dir="$ARTIFACT_ROOT/$phase_name"
  mkdir -p "$snapshot_dir"

  kubectl -n demo-stage get pods \
    -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase \
    >"$snapshot_dir/pods.txt"

  kubectl -n demo-stage get rollout \
    -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.replicas,AVAILABLE:.status.availableReplicas,READY:.status.readyReplicas \
    >"$snapshot_dir/rollouts.txt"

  python3 - "$snapshot_dir/prometheus.json" "$PROM_URL" "$PROM_HOST_HEADER" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

output_path, prom_url, prom_host = sys.argv[1:4]
queries = {
    "gateway_rps": 'sum(rate(http_requests_total{namespace="demo-stage",service="api-gateway"}[1m]))',
    "gateway_5xx": 'sum(rate(http_requests_total{namespace="demo-stage",service="api-gateway",status=~"5.."}[1m]))',
    "gateway_p95_ms": '1000 * histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="demo-stage",service="api-gateway"}[1m])) by (le))',
    "orders_p95_ms": '1000 * histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="demo-stage",service="orders-service"}[1m])) by (le))',
    "payments_p95_ms": '1000 * histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="demo-stage",service="payments-service"}[1m])) by (le))',
    "app_restarts": 'sum(increase(kube_pod_container_status_restarts_total{namespace="demo-stage",container="app"}[10m])) by (pod)',
}

results = {}
for name, query in queries.items():
    url = prom_url + "?" + urllib.parse.urlencode({"query": query})
    headers = {"Host": prom_host} if prom_host else {}
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    results[name] = payload["data"]["result"]

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(results, handle, ensure_ascii=False, indent=2)
PY
}

run_phase() {
  local phase_name="$1"
  local duration="$2"
  local threads="$3"
  local connections="$4"
  local log_file="$ARTIFACT_ROOT/$phase_name/wrk.log"

  mkdir -p "$ARTIFACT_ROOT/$phase_name"
  echo "===== $phase_name =====" | tee "$ARTIFACT_ROOT/$phase_name/meta.txt"
  echo "Started at: $(date --iso-8601=seconds)" | tee -a "$ARTIFACT_ROOT/$phase_name/meta.txt"
  echo "Duration: $duration, threads: $threads, connections: $connections" | tee -a "$ARTIFACT_ROOT/$phase_name/meta.txt"

  wrk \
    -t"$threads" \
    -c"$connections" \
    -d"$duration" \
    --timeout 15s \
    --latency \
    -s "$LUA_SCRIPT" \
    "$TARGET_URL" | tee "$log_file"

  snapshot_state "$phase_name"

  echo "Finished at: $(date --iso-8601=seconds)" | tee -a "$ARTIFACT_ROOT/$phase_name/meta.txt"
  echo | tee -a "$ARTIFACT_ROOT/$phase_name/meta.txt"
}

snapshot_state "pre-flight"

run_phase "phase-01-offpeak" "20m" 4 24
run_phase "phase-02-ramp-up" "30m" 6 48
run_phase "phase-03-morning-spike" "15m" 8 96
run_phase "phase-04-steady" "35m" 8 64
run_phase "phase-05-flash-sale" "15m" 10 192
run_phase "phase-06-lunch-load" "40m" 8 96
run_phase "phase-07-promo-burst" "20m" 10 160
run_phase "phase-08-afternoon-steady" "45m" 8 80
run_phase "phase-09-evening-spike" "20m" 12 224
run_phase "phase-10-prime-time" "40m" 10 96
run_phase "phase-11-wind-down" "20m" 6 48

snapshot_state "post-flight"

echo "Artifacts stored in $ARTIFACT_ROOT"
