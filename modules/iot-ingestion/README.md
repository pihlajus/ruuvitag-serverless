# Module: iot-ingestion

Provisions the AWS IoT Core resources for receiving telemetry from
Raspberry Pi sensors.

## What it creates

- **IoT Thing** — logical device representing a Pi
- **X.509 certificate** — mTLS authentication for the device
- **IoT Policy** — what the device is allowed to publish/subscribe to
- **Policy attachment** — links cert to policy
- **Thing-cert attachment** — links cert to Thing
- **IoT Rule** — routes incoming MQTT messages to the storage backend
  (passed in via input variable)

## Inputs (variables)

| Name | Type | Description |
|------|------|-------------|
| `env` | string | Environment name (dev/prod), used in resource naming |
| `thing_name` | string | Name of the IoT Thing (e.g. "ruuvitag-pi-home") |
| `mqtt_topic_pattern` | string | Topic the Pi publishes to (e.g. "ruuvitag/+/temperature") |
| `target_table_arn` | string | ARN of the Timestream table to write to |

## Outputs

| Name | Description |
|------|-------------|
| `cert_pem` | The Pi's X.509 certificate (sensitive, write to file) |
| `private_key` | The Pi's private key (sensitive) |
| `iot_endpoint` | The MQTT endpoint the Pi connects to |
| `thing_arn` | ARN of the created Thing |

## Notes on the cert

The cert + private key are output as sensitive values. Save them to
local files outside of the repo (or use AWS Secrets Manager) — never
commit them.
