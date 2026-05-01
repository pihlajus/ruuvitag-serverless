#!/usr/bin/env python3
"""Ruuvitag -> AWS IoT Core publisher.

Scans Bluetooth for SCAN_DURATION_SEC, publishes the latest reading
per tag to MQTT topic 'ruuvitag/<mac>/sensor', sleeps the rest of the
interval, repeats.

Configuration is read from environment variables — the systemd unit
file (see ruuvitag.service.example) is the canonical place to set
them. All paths are absolute.

Required:
  IOT_ENDPOINT       e.g. a1abc.iot.eu-north-1.amazonaws.com
  IOT_CLIENT_ID      MQTT client id; must match the IoT Thing name
  IOT_CERT_PATH      X.509 certificate (PEM)
  IOT_KEY_PATH       Private key (PEM)
  IOT_CA_PATH        Root CA (Amazon Root CA 1)

Optional:
  PUBLISH_INTERVAL_SEC   default 60
  SCAN_DURATION_SEC      default 5
"""

import json
import os
import sys
import time

from awscrt import mqtt
from awsiot import mqtt_connection_builder
from ruuvitag_sensor.ruuvi import RuuviTagSensor


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        sys.exit(f"missing required env var: {name}")
    return value


def main() -> None:
    endpoint = env("IOT_ENDPOINT")
    client_id = env("IOT_CLIENT_ID")
    cert_path = env("IOT_CERT_PATH")
    key_path = env("IOT_KEY_PATH")
    ca_path = env("IOT_CA_PATH")
    publish_interval = int(env("PUBLISH_INTERVAL_SEC", "60"))
    scan_duration = int(env("SCAN_DURATION_SEC", "5"))

    print(f"connecting to {endpoint} as {client_id}", flush=True)
    conn = mqtt_connection_builder.mtls_from_path(
        endpoint=endpoint,
        cert_filepath=cert_path,
        pri_key_filepath=key_path,
        ca_filepath=ca_path,
        client_id=client_id,
        clean_session=False,
        keep_alive_secs=60,
    )
    conn.connect().result()
    print("connected", flush=True)

    try:
        while True:
            print(f"scanning bluetooth for {scan_duration}s", flush=True)
            readings = RuuviTagSensor.get_data_for_sensors(
                search_duratio_sec=scan_duration
            )
            print(f"found {len(readings)} tags", flush=True)

            for mac, data in readings.items():
                topic = f"ruuvitag/{mac.replace(':', '')}/sensor"
                payload = json.dumps(
                    {
                        "mac": mac,
                        "ts_ms": int(time.time() * 1000),
                        "temperature": data.get("temperature"),
                        "humidity": data.get("humidity"),
                        "pressure": data.get("pressure"),
                        "battery": data.get("battery"),
                        "rssi": data.get("rssi"),
                    }
                )
                fut, _ = conn.publish(
                    topic=topic, payload=payload, qos=mqtt.QoS.AT_LEAST_ONCE
                )
                fut.result()
                print(
                    f"  -> {topic} temp={data.get('temperature')} hum={data.get('humidity')}",
                    flush=True,
                )

            sleep_s = max(1, publish_interval - scan_duration)
            print(f"sleeping {sleep_s}s", flush=True)
            time.sleep(sleep_s)
    except KeyboardInterrupt:
        print("stopping", flush=True)
    finally:
        conn.disconnect().result()
        print("disconnected", flush=True)


if __name__ == "__main__":
    main()
