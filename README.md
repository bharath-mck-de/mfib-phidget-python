# Phidget → HiveMQ (Python production publisher)

Host-native Python publisher for a Windows PC fleet. Reads a Phidget VINT Hub voltage input over **USB**, converts to current (amps), and publishes MFIB telemetry to HiveMQ.

Develop on **macOS**, deploy to **Windows** production stations. No Docker or Phidget Network Server required on the host.

## Architecture

```
USB Phidget VINT Hub
        │
        ▼
Python publisher (this project, runs on host)
        │
        ▼
HiveMQ MQTT broker (local for dev, central LAN for prod)
```

Compared to [`11-nodered-phidget`](../11-nodered-phidget): this project talks to the Phidget directly via USB. Node-RED in Docker requires Phidget Network Server on the host as an extra hop.

## Prerequisites

### Every host (Mac dev or Windows station)

1. Python 3.10+
2. [Phidget drivers](https://www.phidgets.com/downloads/) installed
3. Phidget VINT Hub connected via USB
4. Git Bash, WSL, or SSH to run `.sh` scripts on Windows

### MQTT broker

**Local dev (Mac):** start HiveMQ from the sibling project:

```bash
cd ../10-hivemq-broker
./scripts/setup.sh
```

Set `MQTT_BROKER_HOST=127.0.0.1` in `.env` (host connects to the published port).

**Production (Windows fleet):** set `MQTT_BROKER_HOST` to your central LAN broker IP/hostname.

## Quick start

```bash
chmod +x scripts/*.sh
./scripts/reset.sh
# edit .env — set WORKSTATION, DEVICE_ID, PHIDGET_HUB_PORT, PHIDGET_SERIAL

./scripts/start.sh
```

## Day-to-day commands

```bash
./scripts/start.sh    # start publisher in background
./scripts/stop.sh     # stop publisher
./scripts/status.sh   # process, broker, recent log lines
./scripts/reset.sh    # create .env (if missing) and reinstall deps
```

Run locally or via SSH:

```bash
ssh user@station "cd /path/to/12-phidget-python-prod && ./scripts/start.sh"
```

## Configuration

All settings live in **`.env`** on each PC. Copy from `.env.example`:

```bash
cp .env.example .env
# or: ./scripts/reset.sh   (creates .env automatically if missing)
```

### What to change per workstation

| Variable | Example | Description |
|---|---|---|
| `WORKSTATION` | `filling-1` | MFIB topic segment |
| `DEVICE_ID` | `filler01` | MFIB topic segment |
| `PHIDGET_HUB_PORT` | `2` | VINT port (0–5) |
| `PHIDGET_SERIAL` | `781463` | Hub serial number |
| `MQTT_BROKER_HOST` | `127.0.0.1` | Local dev or central broker IP |

Everything else has sensible defaults. `MQTT_TOPIC` is built automatically when left blank:

```
mfib/munich/{WORKSTATION}/{DEVICE_ID}/telemetry
```

### Optional settings

| Variable | Default | Description |
|---|---|---|
| `MQTT_BROKER_PORT` | `1883` | Broker port |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | empty | Broker auth |
| `MQTT_CLIENT_ID` | `phidget-{DEVICE_ID}` | MQTT client name |
| `SENSOR_AMPS_OFFSET` | `2.5` | 75 A transducer default |
| `SENSOR_AMPS_VOLTS_RATIO` | `0.02083` | Calibration ratio |
| `PUBLISH_INTERVAL_MS` | `1000` | Throttle on voltage change |
| `LOG_LEVEL` | `INFO` | Log verbosity |
| `LOG_FILE` | `logs/publisher.log` | Log path |

### Production broker example

```env
MQTT_BROKER_HOST=192.168.1.50
MQTT_USERNAME=publisher
MQTT_PASSWORD=your-password
```

Restart: `./scripts/stop.sh && ./scripts/start.sh`

## Reset script (`reset.sh`)

`reset.sh` prepares the environment:

- Creates `.env` from `.env.example` if `.env` does not exist yet
- Creates `.venv` and runs `pip install -r requirements.txt`
- Derives `MQTT_TOPIC` when empty

Existing `.env` files are **not** overwritten. Edit `.env` directly to change settings.

## MFIB payload

Published to `mfib/munich/{workstation}/{device_id}/telemetry`:

```json
{
  "timestamp": "2026-06-11T10:30:00.000Z",
  "device_id": "filler01",
  "workstation": "filling-1",
  "metrics": {
    "voltage_v": 2.5123,
    "current_a": 0.5906
  }
}
```

Subscribe to verify:

```bash
cd ../10-hivemq-broker
python scripts/test_mqtt.py --subscribe "mfib/munich/filling-1/filler01/telemetry"
```

## Fleet rollout (new Windows PC)

1. Install Python 3.10+ and Phidget drivers
2. Copy this project folder to the station
3. `./scripts/reset.sh` then edit `.env` for that PC
4. `./scripts/start.sh`

## Troubleshooting

| Symptom | Fix |
|---|---|
| `hub_port is not set` / missing env | Run `reset.sh`; check `.env` |
| Phidget attachment timeout | USB connection, serial number, hub port; close other apps using the hub |
| MQTT connection refused | Start HiveMQ or check `MQTT_BROKER_HOST` / port |
| Publisher already running | `./scripts/stop.sh` then `start.sh` |
| Wrong current readings | Adjust `SENSOR_AMPS_OFFSET` and `SENSOR_AMPS_VOLTS_RATIO` |

## Related projects

- [`09-phidget-sensors`](../09-phidget-sensors) — original Python voltage → current reference
- [`11-nodered-phidget`](../11-nodered-phidget) — Node-RED + Docker prototype
- [`10-hivemq-broker`](../10-hivemq-broker) — HiveMQ broker and MFIB topic conventions
