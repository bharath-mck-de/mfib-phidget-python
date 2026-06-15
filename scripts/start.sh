#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

PID_FILE="run/publisher.pid"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Run ./scripts/reset.sh first." >&2
  exit 1
fi

if [[ -f "${PID_FILE}" ]]; then
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    echo "Publisher already running (pid ${pid}). Stop it first: ./scripts/stop.sh" >&2
    exit 1
  fi
  rm -f "${PID_FILE}"
fi

if [[ -f .venv/bin/python ]]; then
  PYTHON=".venv/bin/python"
elif [[ -f .venv/Scripts/python.exe ]]; then
  PYTHON=".venv/Scripts/python.exe"
else
  echo "ERROR: Virtual environment not found. Run ./scripts/reset.sh first." >&2
  exit 1
fi

mkdir -p logs run

# shellcheck disable=SC1091
set -a
source .env
set +a

nohup "${PYTHON}" src/publish_current.py >> "${LOG_FILE:-logs/publisher.log}" 2>&1 &
echo $! > "${PID_FILE}"

echo "Publisher started (pid $(cat "${PID_FILE}"))."
echo "  Log file: ${LOG_FILE:-logs/publisher.log}"
./scripts/status.sh
