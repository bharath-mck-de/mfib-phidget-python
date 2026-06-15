#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

PID_FILE="run/publisher.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "Publisher is not running (no pid file)."
  exit 0
fi

pid="$(cat "${PID_FILE}")"
if kill -0 "${pid}" 2>/dev/null; then
  kill "${pid}"
  echo "Stopped publisher (pid ${pid})."
else
  echo "Publisher not running (stale pid ${pid})."
fi

rm -f "${PID_FILE}"
