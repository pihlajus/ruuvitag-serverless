# Migration plan

Notes on moving from the legacy EC2/InfluxDB setup to this serverless
stack. Kept short on purpose — this is a home project.

## Legacy stack

A single t3.micro running 2020 — early 2026 in `eu-north-1`:

- Nginx + Let's Encrypt
- InfluxDB 1.7 (data on a separate 30 GB EBS volume mounted at
  `/data/influxdb`, ~4 GB used)
- Grafana
- Public IPv4, SSH and InfluxDB ports open to allow the home Pi to push

Ansible-provisioned, originally driven by a small Terraform 0.x
repository. The Pi runs an `aws-ruuvi-collector` Java service that
posts readings via HTTP to the InfluxDB endpoint.

Approximate monthly cost: ~$19 (compute, EBS gp2, public IPv4, Route 53).

## Target stack

```
Raspberry Pi
  │ MQTT over mTLS (X.509)
  ▼
AWS IoT Core
  │ IoT Topic Rule
  ▼
DynamoDB (on-demand)
  │
  ▼
Grafana Cloud
```

Estimated monthly cost: ~$2-5 depending on Route 53 / domain choices.

## Why DynamoDB instead of Timestream

Timestream would be a more natural choice for time-series data, but it
isn't available in `eu-north-1` where the rest of this account lives.
DynamoDB on-demand is fine for the volume here:

- 4 sensors × ~1 reading / minute → ~170k writes / month
- $1.25 per 1M write requests → ~$0.21 / month
- Storage: a few cents on top
- Queries by `mac` + time range are efficient on the composite key

If the volume grows or we ever need cross-region, DynamoDB is also
trivial to swap out — the IoT Rule action is the only consumer.

## Migration order

1. **Stand up the new stack** — `bootstrap` then `environments/home`
2. **Verify end-to-end** with `aws iot-data publish` → check DynamoDB
3. **Switch the Pi** to the new MQTT publisher (Python + venv on Pi,
   cert + key from `terraform output`)
4. **Run both publishers in parallel** for a week so we can compare
5. **Migrate historical data** from InfluxDB to DynamoDB so Grafana
   sees the full timeline
6. **Decommission the EC2** — final EBS snapshot to S3 archive, then
   `terraform destroy` on the legacy repo

Step 5 is optional. For a home project the trade-off is real: ~12M
records × $1.25/1M = $15 to batch-import, vs $0 to start fresh and
keep the old volume as an archived snapshot. DynamoDB Import from S3
would bring the cost down to under a dollar but produces a separate
table.

## Open questions

- Pi runs Raspbian Buster which is EOL — the OS upgrade should happen
  alongside the publisher swap, not before, to avoid breaking the
  existing collector mid-migration.
- Grafana Cloud free tier has a 14-day metric retention; longer-term
  history stays in DynamoDB and is queried on demand by the Cloud
  datasource.
