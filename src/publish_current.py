#!/usr/bin/env python3
"""Read Phidget VINT voltage input, convert to current, publish MFIB telemetry to MQTT."""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import threading
import time
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path

import paho.mqtt.client as mqtt
from dotenv import load_dotenv
from Phidget22.Devices.VoltageInput import VoltageInput

PROJECT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_DIR / ".env")

_shutdown = threading.Event()
_last_publish_ms = 0.0
_last_publish_lock = threading.Lock()


def env_required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"{name} is not set in the environment")
    return value


def env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return float(raw)


def env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return int(raw)


def derive_mqtt_topic() -> str:
    topic = os.getenv("MQTT_TOPIC", "").strip()
    if topic:
        return topic
    workstation = env_required("WORKSTATION")
    device_id = env_required("DEVICE_ID")
    return f"mfib/munich/{workstation}/{device_id}/telemetry"


def setup_logging() -> logging.Logger:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    log = logging.getLogger("phidget_publisher")
    log.setLevel(level)
    log.handlers.clear()

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    log.addHandler(console)

    log_file = os.getenv("LOG_FILE", "logs/publisher.log")
    log_path = PROJECT_DIR / log_file
    log_path.parent.mkdir(parents=True, exist_ok=True)
    file_handler = RotatingFileHandler(
        log_path,
        maxBytes=1_000_000,
        backupCount=3,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    log.addHandler(file_handler)

    return log


def volts_to_amps(voltage: float) -> float:
    offset = env_float("SENSOR_AMPS_OFFSET", 2.5)
    ratio = env_float("SENSOR_AMPS_VOLTS_RATIO", 0.02083)
    return (voltage - offset) / ratio


def should_publish(now_ms: float) -> bool:
    global _last_publish_ms
    interval = env_int("PUBLISH_INTERVAL_MS", 1000)
    with _last_publish_lock:
        if now_ms - _last_publish_ms < interval:
            return False
        _last_publish_ms = now_ms
        return True


def build_payload(voltage_v: float, current_a: float) -> dict:
    return {
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "device_id": env_required("DEVICE_ID"),
        "workstation": env_required("WORKSTATION"),
        "metrics": {
            "voltage_v": round(voltage_v, 4),
            "current_a": round(current_a, 4),
        },
    }


class MqttPublisher:
    def __init__(self, log: logging.Logger, topic: str) -> None:
        self.log = log
        self.topic = topic
        self._connected = threading.Event()
        client_id = os.getenv("MQTT_CLIENT_ID") or f"phidget-{env_required('DEVICE_ID')}"
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=client_id,
            protocol=mqtt.MQTTv311,
        )
        username = os.getenv("MQTT_USERNAME", "").strip()
        password = os.getenv("MQTT_PASSWORD", "").strip()
        if username:
            self.client.username_pw_set(username, password or None)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect

    def _on_connect(
        self,
        client: mqtt.Client,
        _userdata,
        _flags,
        reason_code: mqtt.ReasonCode,
        _properties=None,
    ) -> None:
        if reason_code == 0:
            self.log.info("MQTT connected")
            self._connected.set()
        else:
            self.log.error("MQTT connect failed: %s", reason_code)

    def _on_disconnect(
        self,
        _client: mqtt.Client,
        _userdata,
        _flags,
        reason_code: mqtt.ReasonCode,
        _properties=None,
    ) -> None:
        self._connected.clear()
        if reason_code != 0:
            self.log.warning("MQTT disconnected: %s", reason_code)

    def connect(self) -> None:
        host = env_required("MQTT_BROKER_HOST")
        port = env_int("MQTT_BROKER_PORT", 1883)
        self.log.info("Connecting to MQTT broker %s:%s", host, port)
        self.client.connect(host, port, keepalive=60)
        self.client.loop_start()
        if not self._connected.wait(timeout=10):
            raise RuntimeError("MQTT connection timed out")

    def publish(self, payload: dict) -> None:
        body = json.dumps(payload)
        info = self.client.publish(self.topic, body, qos=0, retain=False)
        if info.rc != mqtt.MQTT_ERR_SUCCESS:
            self.log.error("MQTT publish failed: rc=%s", info.rc)
            return
        self.log.info("Published to %s: %s", self.topic, body)

    def disconnect(self) -> None:
        self.client.loop_stop()
        self.client.disconnect()


def run_publisher(log: logging.Logger) -> None:
    topic = derive_mqtt_topic()
    mqtt_pub = MqttPublisher(log, topic)
    mqtt_pub.connect()

    voltage_input = VoltageInput()
    voltage_input.setIsHubPortDevice(True)
    voltage_input.setHubPort(env_int("PHIDGET_HUB_PORT", 0))
    voltage_input.setDeviceSerialNumber(env_int("PHIDGET_SERIAL", -1))
    open_timeout = env_int("PHIDGET_OPEN_TIMEOUT_MS", 5000)

    def on_voltage_change(_channel, voltage: float) -> None:
        if _shutdown.is_set():
            return
        now_ms = time.monotonic() * 1000
        if not should_publish(now_ms):
            return
        current_a = volts_to_amps(voltage)
        payload = build_payload(voltage, current_a)
        mqtt_pub.publish(payload)

    voltage_input.setOnVoltageChangeHandler(on_voltage_change)

    log.info(
        "Opening Phidget VoltageInput (serial=%s, hub_port=%s)",
        os.getenv("PHIDGET_SERIAL"),
        os.getenv("PHIDGET_HUB_PORT"),
    )
    voltage_input.openWaitForAttachment(open_timeout)
    log.info("Phidget attached — publishing to %s", topic)

    try:
        while not _shutdown.is_set():
            time.sleep(0.25)
    finally:
        log.info("Closing Phidget and MQTT connections")
        voltage_input.close()
        mqtt_pub.disconnect()


def main() -> int:
    log = setup_logging()

    def handle_signal(signum, _frame) -> None:
        log.info("Received signal %s — shutting down", signum)
        _shutdown.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    try:
        run_publisher(log)
    except Exception:
        log.exception("Publisher failed")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
