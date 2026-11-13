#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo ./scripts/verify-services.sh" >&2
  exit 1
fi

for service in prometheus node_exporter grafana-server; do
  echo "Checking ${service}..."
  systemctl is-active --quiet "${service}" || {
    echo "Service is not active: ${service}" >&2
    systemctl status "${service}" --no-pager || true
    exit 1
  }
done

echo "Checking Prometheus readiness..."
curl -fsS --retry 10 --retry-connrefused --retry-delay 2 http://localhost:9090/-/ready
echo

echo "Checking Node Exporter metrics..."
METRICS_FILE="$(mktemp)"
trap 'rm -f "${METRICS_FILE}"' EXIT
curl -fsS --retry 10 --retry-connrefused --retry-delay 2 http://localhost:9100/metrics -o "${METRICS_FILE}"
grep -m 1 '^node_cpu_seconds_total' "${METRICS_FILE}"

echo "Checking Grafana health..."
curl -fsS --retry 10 --retry-connrefused --retry-delay 2 http://localhost:3000/api/health
echo

echo "All three services are active and their local endpoints respond."
echo "Check scrape target states at http://localhost:9090/targets"
