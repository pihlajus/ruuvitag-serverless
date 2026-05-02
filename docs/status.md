# Status

Migration done. Stack is live, archive backfilled, EC2 retired.

## Live

- Pi (`/opt/ruuvitag/ruuvitag_publish.py` under systemd) reads BLE
  every minute and publishes to AWS IoT Core over MQTT/mTLS.
- IoT Topic Rules fan messages to:
  - DynamoDB `ruuvitag-readings-home` (live archive, mac-keyed)
  - `metrics-publisher` Lambda → Grafana Cloud Mimir (Influx line
    protocol, 14-day metrics retention)
- `archive-sync` Lambda runs daily and copies yesterday's rows from
  the live table into `ruuvitag-readings-historical-home` keyed on
  the human-readable sensor name.
- `archive-query` Lambda Function URL serves time-series JSON to the
  Grafana Infinity datasource for the archive dashboard.
- `alert-watcher` Lambda checks every hour and emails via SNS when
  any sensor has been silent past the threshold (default 120 min,
  taking into account the ~1h45m worst case observed for the Ulko
  sensor behind a thick wall).

## Dashboards

- `Ruuvitag — live (Prometheus)` — daily-driver, last 14 days. JSON
  in `docs/grafana/ruuvitag-live.json`.
- `Ruuvitag — archive (DynamoDB)` — long-term history (2020-03 →
  today, daily-synced). JSON in `docs/grafana/ruuvitag-archive.json`.

## Decommissioned

- EC2 instance `i-05e96a2b1e3f50d72` terminated on 2026-05-02
- 30 GB data EBS volume deleted (data preserved as
  snapshot `snap-06cef1807f148ea01`, ~$0.22/month standard tier)
- Security group `home_monitor_default_secgroup` deleted
- Route 53 A record `koti.atkpihlainen.fi` deleted

## Open future ideas

- Move EBS snapshot to archive tier (~$0.05/month, 75% cheaper, 24-72h
  restore time) once we're confident we'll never need it back fast.
- Tune Pi BLE scan duration further if the Ulko sensor still drops
  out occasionally — currently at 15s scan, 60s publish interval.
- If volume grows beyond the Free tier on Grafana Cloud, reconsider
  the metrics-publisher push frequency or aggregate before pushing.

## Notes

- Originally planned with Timestream, switched to DynamoDB after
  noticing Timestream is not available in `eu-north-1`.
- Pi runs Raspbian Buster; awsiotsdk + ruuvitag-sensor work via venv
  but awscrt has to compile from source on armv7l — takes ~30 min.
- KMS customer-managed key for Terraform state encryption is the
  single largest cost line at $1/month. Could drop to S3-default
  AES256 to save it but the audit/rotation features are nice.
