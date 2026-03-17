#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_GATEWAY_SERVICE_IP="$(kubectl -n demo-stage get svc api-gateway -o jsonpath='{.spec.clusterIP}')"
PROMETHEUS_SERVICE_IP="$(kubectl -n monitoring get svc kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')"

TARGET_URL="${TARGET_URL:-http://${API_GATEWAY_SERVICE_IP}:8080}"
LUA_SCRIPT="${LUA_SCRIPT:-$REPO_ROOT/scripts/loadtest/gateway-checkout-heavy-stage.lua}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-$REPO_ROOT/.loadtest/stage-100k-online-$(date +%Y%m%d-%H%M%S)}"
PROM_URL="${PROM_URL:-http://${PROMETHEUS_SERVICE_IP}:9090/api/v1/query}"

mkdir -p "$ARTIFACT_ROOT"

# Single-node VPS tuning so the load generator can open more client sockets.
sudo -n sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1 || true
sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1 || true

# Give the stage namespace enough surge headroom for the heavier runtime profile.
kubectl -n demo-stage patch resourcequota demo-stage-quota --type merge -p '{"spec":{"hard":{"limits.memory":"14Gi"}}}' >/dev/null 2>&1 || true

ulimit -n 131072 || true

monitor_resources() {
  while true; do
    local ts
    ts="$(date --iso-8601=seconds)"
    {
      echo "=== $ts ==="
      kubectl top node || true
      echo "--- pods ---"
      kubectl top pods -n demo-stage || true
      echo "--- status ---"
      kubectl -n demo-stage get pods \
        -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase || true
      echo
    } >>"$ARTIFACT_ROOT/resource-samples.log"
    sleep 15
  done
}

snapshot_state() {
  local phase_name="$1"
  local snapshot_dir="$ARTIFACT_ROOT/$phase_name"
  mkdir -p "$snapshot_dir"

  kubectl -n demo-stage get pods \
    -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase \
    >"$snapshot_dir/pods.txt"

  kubectl -n demo-stage get rollout \
    -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.replicas,UPDATED:.status.updatedReplicas,AVAILABLE:.status.availableReplicas \
    >"$snapshot_dir/rollouts.txt"

  python3 - "$snapshot_dir/prometheus.json" "$PROM_URL" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

output_path, prom_url = sys.argv[1:3]
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
    with urllib.request.urlopen(url, timeout=20) as response:
        payload = json.load(response)
    results[name] = payload["data"]["result"]

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(results, handle, ensure_ascii=False, indent=2)
PY
}

run_phase() {
  local phase_name="$1"
  local duration="$2"
  local threads_per_process="$3"
  local connections_per_process="$4"
  local process_count="$5"
  local phase_dir="$ARTIFACT_ROOT/$phase_name"
  local idx
  local fail=0
  local pids=()

  mkdir -p "$phase_dir"
  {
    echo "===== $phase_name ====="
    echo "Started at: $(date --iso-8601=seconds)"
    echo "Duration: $duration"
    echo "Processes: $process_count"
    echo "Threads per process: $threads_per_process"
    echo "Connections per process: $connections_per_process"
    echo "Target URL: $TARGET_URL"
  } | tee "$phase_dir/meta.txt"

  for idx in $(seq 1 "$process_count"); do
    wrk \
      -t"$threads_per_process" \
      -c"$connections_per_process" \
      -d"$duration" \
      --timeout 30s \
      --latency \
      -s "$LUA_SCRIPT" \
      "$TARGET_URL" >"$phase_dir/wrk-$idx.log" 2>&1 &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || fail=1
  done

  snapshot_state "$phase_name"

  {
    echo "Finished at: $(date --iso-8601=seconds)"
    echo "Phase failure flag: $fail"
    echo
  } | tee -a "$phase_dir/meta.txt"
}

monitor_resources &
MONITOR_PID=$!
cleanup() {
  kill "$MONITOR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

snapshot_state "pre-flight"

# 100k online users are modeled here as a harsh active-user profile on a single-box generator:
# sustained heavy checkout traffic, long hot phases, and explicit high-concurrency spikes.
run_phase "phase-01-heavy-baseline" "20m" 8 1000 4
run_phase "phase-02-ramp-6k" "30m" 8 1500 4
run_phase "phase-03-ramp-8k" "30m" 8 2000 4
run_phase "phase-04-spike-10k" "20m" 8 2500 4
run_phase "phase-05-sustain-8k" "40m" 8 2000 4
run_phase "phase-06-burst-12k" "15m" 8 2000 6
run_phase "phase-07-sustain-9k" "45m" 8 2250 4
run_phase "phase-08-evening-spike-12k" "20m" 8 2000 6
run_phase "phase-09-prime-time-9k" "45m" 8 2250 4
run_phase "phase-10-flash-sale-15k" "15m" 8 2500 6
run_phase "phase-11-wind-down-6k" "20m" 8 1500 4

snapshot_state "post-flight"
cleanup
trap - EXIT

echo "Artifacts stored in $ARTIFACT_ROOT"
