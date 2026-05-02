# Status

Quick note on what's done and what's still on the TODO list.

## Done

- Bootstrap stack (S3 + DynamoDB lock + KMS) for Terraform state
- `iot-ingestion` module: IoT Thing, certificate, policy
- `timeseries-storage` module: DynamoDB table + IAM role
- `environments/home` composing both modules + the IoT Topic Rule
- End-to-end check: `aws iot-data publish` lands a row in DynamoDB
- `metrics-publisher` module: Lambda forwards readings to Grafana
  Cloud via Influx line protocol; deploys with empty creds and waits
  for real ones to be filled in
- `historical.tf`: migration S3 bucket + archive DynamoDB table
  (created via S3 Import on apply)
- `scripts/migrate_influx_to_s3.py`: downsamples and uploads NDJSON
  per month with progress logging
- Grafana JSON for the live (Prometheus) dashboard committed to
  `docs/grafana/ruuvitag-live.json`; archive dashboard query
  reference in `docs/grafana/ruuvitag-archive.queries.md`

## TODO

- Switch the Pi from the old Java `aws-ruuvi-collector` to
  `pi/ruuvitag_publish.py` under systemd (certs from
  `terraform output`). Currently the legacy Java daemons still write
  to InfluxDB on the EC2 — fine for the historical migration, but
  needs to flip before EC2 shutdown.
- Sign up for Grafana Cloud Free, create a Metrics API key
  (`metrics:write` scope) plus an Influx push URL, set them in
  `terraform.tfvars`, and re-apply to wire the Lambda up to the live
  dashboard.
- Run the historical migration end-to-end: downsample + export +
  S3 Import via `terraform apply`, verify the archive dashboard.
- After ~2 weeks of parallel running: snapshot EBS to Glacier Deep
  Archive, terminate the EC2, release the EIP, drop DNS.

## Notes

- Originally planned with Timestream, switched to DynamoDB after
  noticing Timestream is not available in `eu-north-1`. For 4 sensors
  at 1-minute intervals the cost is in the cents per month either way.
- Pi runs Raspbian Buster; awsiotsdk + ruuvitag-sensor work via venv
  but awscrt has to compile from source on armv7l — takes ~30 min.
