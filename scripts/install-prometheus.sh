#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-3.5.0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo ./scripts/install-prometheus.sh" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m). Use x86_64 or aarch64." >&2
    exit 1
    ;;
esac

for command in curl tar systemctl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
ARCHIVE="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${ARCHIVE}"

echo "Downloading Prometheus ${PROMETHEUS_VERSION} for ${ARCH}..."
curl -fL --retry 3 --retry-delay 2 "${URL}" -o "${TEMP_DIR}/${ARCHIVE}"
tar -xzf "${TEMP_DIR}/${ARCHIVE}" -C "${TEMP_DIR}"
EXTRACTED_DIR="${TEMP_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}"

if ! id -u prometheus >/dev/null 2>&1; then
  useradd --system --user-group --no-create-home --shell /usr/sbin/nologin prometheus
fi

install -d -o prometheus -g prometheus /etc/prometheus /var/lib/prometheus
install -m 0755 "${EXTRACTED_DIR}/prometheus" /usr/local/bin/prometheus
install -m 0755 "${EXTRACTED_DIR}/promtool" /usr/local/bin/promtool
cp -a "${EXTRACTED_DIR}/consoles" /etc/prometheus/
cp -a "${EXTRACTED_DIR}/console_libraries" /etc/prometheus/
install -m 0644 "${PROJECT_DIR}/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
install -m 0644 "${PROJECT_DIR}/prometheus/prometheus.service" /etc/systemd/system/prometheus.service
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

echo "Validating Prometheus configuration..."
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
systemctl daemon-reload
systemctl enable --now prometheus
systemctl restart prometheus

echo "Prometheus installed. Check with: systemctl status prometheus --no-pager"
echo "Prometheus UI: http://localhost:9090"
