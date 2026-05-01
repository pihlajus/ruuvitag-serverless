# Status

Quick note on what's done and what's still on the TODO list.

## Done

- Bootstrap stack (S3 + DynamoDB lock + KMS) for Terraform state
- `iot-ingestion` module: IoT Thing, certificate, policy
- `timeseries-storage` module: DynamoDB table + IAM role
- `environments/home` composing both modules + the IoT Topic Rule
- End-to-end check: `aws iot-data publish` lands a row in DynamoDB

## TODO

- Switch the Pi from the old InfluxDB publisher to the new MQTT one
  (Python script + systemd unit, certs from `terraform output`)
- Migrate historical readings from the old InfluxDB → DynamoDB so
  Grafana sees the full timeline
- Grafana Cloud datasource pointing at DynamoDB; rebuild dashboards
- Decommission the old EC2 + EBS volumes; archive a final snapshot

## Notes

- Originally planned with Timestream, switched to DynamoDB after
  noticing Timestream is not available in `eu-north-1`. For 4 sensors
  at 1-minute intervals the cost is in the cents per month either way.
- Pi runs Raspbian Buster; awsiotsdk + ruuvitag-sensor work via venv
  but awscrt has to compile from source on armv7l — takes ~30 min.
