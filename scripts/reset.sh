#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example — edit WORKSTATION, DEVICE_ID, and Phidget settings."
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

: "${WORKSTATION:=filling-1}"
: "${DEVICE_ID:=phidget-gateway}"

if [[ -z "${WORKSTATION}" || -z "${DEVICE_ID}" ]]; then
  echo "ERROR: WORKSTATION and DEVICE_ID must be set in .env" >&2
  exit 1
fi

if [[ -z "${PHIDGET_HUB_PORT:-}" || -z "${PHIDGET_SERIAL:-}" ]]; then
  echo "ERROR: PHIDGET_HUB_PORT and PHIDGET_SERIAL must be set in .env" >&2
  exit 1
fi

if [[ -z "${MQTT_TOPIC:-}" ]]; then
  MQTT_TOPIC="mfib/munich/${WORKSTATION}/${DEVICE_ID}/telemetry"
  if grep -q '^MQTT_TOPIC=' .env; then
    sed -i.bak "s|^MQTT_TOPIC=.*|MQTT_TOPIC=${MQTT_TOPIC}|" .env && rm -f .env.bak
  else
    echo "MQTT_TOPIC=${MQTT_TOPIC}" >> .env
  fi
  echo "Set MQTT_TOPIC=${MQTT_TOPIC}"
fi

mkdir -p logs run

if [[ ! -d .venv ]]; then
  echo "Creating Python virtual environment..."
  python3 -m venv .venv
fi

if [[ -f .venv/bin/python ]]; then
  PYTHON=".venv/bin/python"
  PIP=".venv/bin/pip"
elif [[ -f .venv/Scripts/python.exe ]]; then
  PYTHON=".venv/Scripts/python.exe"
  PIP=".venv/Scripts/pip.exe"
else
  echo "ERROR: Could not find Python in .venv" >&2
  exit 1
fi

echo "Installing dependencies..."
"${PIP}" install -r requirements.txt

echo ""
echo "Reset complete."
echo "  Config:  .env"
echo "  MQTT:    ${MQTT_TOPIC}"
echo "  Broker:  ${MQTT_BROKER_HOST:-127.0.0.1}:${MQTT_BROKER_PORT:-1883}"
echo "  Phidget: USB hub port ${PHIDGET_HUB_PORT}, serial ${PHIDGET_SERIAL}"
echo ""
echo "Start publisher: ./scripts/start.sh"
echo "Check status:    ./scripts/status.sh"
