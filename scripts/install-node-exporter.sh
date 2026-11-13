#!/usr/bin/env bash
set -euo pipefail

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.9.1}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo ./scripts/install-node-exporter.sh" >&2
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
ARCHIVE="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${ARCHIVE}"

echo "Downloading Node Exporter ${NODE_EXPORTER_VERSION} for ${ARCH}..."
curl -fL --retry 3 --retry-delay 2 "${URL}" -o "${TEMP_DIR}/${ARCHIVE}"
tar -xzf "${TEMP_DIR}/${ARCHIVE}" -C "${TEMP_DIR}"
EXTRACTED_DIR="${TEMP_DIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}"

if ! id -u node_exporter >/dev/null 2>&1; then
  useradd --system --user-group --no-create-home --shell /usr/sbin/nologin node_exporter
fi

install -m 0755 "${EXTRACTED_DIR}/node_exporter" /usr/local/bin/node_exporter
install -m 0644 "${PROJECT_DIR}/node-exporter/node_exporter.service" /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl enable --now node_exporter

echo "Node Exporter installed. Check with: systemctl status node_exporter --no-pager"
echo "Metrics endpoint: http://localhost:9100/metrics"
