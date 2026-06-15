#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

PID_FILE="run/publisher.pid"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

: "${MQTT_BROKER_HOST:=127.0.0.1}"
: "${MQTT_BROKER_PORT:=1883}"
: "${LOG_FILE:=logs/publisher.log}"

echo "=== Publisher process ==="
if [[ -f "${PID_FILE}" ]]; then
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    echo "  OK  running (pid ${pid})"
  else
    echo "  FAIL  stale pid file (${pid})"
  fi
else
  echo "  FAIL  not running"
fi

echo ""
echo "=== MQTT broker (${MQTT_BROKER_HOST}:${MQTT_BROKER_PORT}) ==="
if command -v nc >/dev/null 2>&1; then
  if nc -z -w 3 "${MQTT_BROKER_HOST}" "${MQTT_BROKER_PORT}" 2>/dev/null; then
    echo "  OK  ${MQTT_BROKER_HOST}:${MQTT_BROKER_PORT} reachable"
  else
    echo "  FAIL  ${MQTT_BROKER_HOST}:${MQTT_BROKER_PORT} not reachable"
  fi
else
  echo "  SKIP  nc not available"
fi

if [[ -n "${MQTT_TOPIC:-}" ]]; then
  echo ""
  echo "=== Config ==="
  echo "  Topic:       ${MQTT_TOPIC}"
  echo "  Workstation: ${WORKSTATION:-}"
  echo "  Device:      ${DEVICE_ID:-}"
  echo "  Phidget:     hub port ${PHIDGET_HUB_PORT:-}, serial ${PHIDGET_SERIAL:-}"
fi

log_path="${PROJECT_DIR}/${LOG_FILE}"
echo ""
echo "=== Log (${LOG_FILE}) ==="
if [[ -f "${log_path}" ]]; then
  tail -n 5 "${log_path}" | sed 's/^/  /'
else
  echo "  (no log file yet)"
fi
