# Migration plan

Notes on moving from the legacy EC2/InfluxDB setup to this serverless
stack. Kept short on purpose — this is a home project.

## Legacy stack

A single t3.micro running 2020 — early 2026 in `eu-north-1`:

- Nginx + Let's Encrypt
- InfluxDB 1.7 (data on a separate 30 GB EBS volume mounted at
  `/data/influxdb`, ~4 GB used, 313 weekly shards)
- Grafana
- Public IPv4, SSH and InfluxDB ports open to allow the home Pi to push

Ansible-provisioned, originally driven by a small Terraform 0.x
repository. The Pi runs an `aws-ruuvi-collector` Java service that
posts readings via HTTP to the InfluxDB endpoint.

Approximate monthly cost: ~$15 (compute, EBS gp2, public IPv4).

## Target stack

```
Raspberry Pi
  │ MQTT over mTLS (X.509)
  ▼
AWS IoT Core
  ├── IoT Topic Rule ─→ DynamoDB (full archive, queryable)
  └── IoT Topic Rule ─→ Lambda ─→ Grafana Cloud Prometheus
                                  (last 14 days, fast dashboards)
```

Estimated monthly cost: **~$0.75** (mostly DynamoDB storage and IoT
Core message charges; Lambda and Grafana Cloud stay inside the always-
free tiers at this volume).

## Why DynamoDB + Prometheus side-by-side

InfluxDB on the box served two purposes: long-term storage *and* the
query backend Grafana talked to. Splitting them:

- **DynamoDB** handles long-term storage. On-demand pricing, ~$0.20 / M
  writes, and storage is a few cents per GB. Six years of 1-minute
  data fits in ~2 GB.
- **Grafana Cloud Prometheus** handles live dashboards. The Free tier
  retains 14 days of metrics — enough for day-to-day monitoring, and
  PromQL is much nicer than DynamoDB's query API for time-series
  panels.

For history older than 14 days, a second Grafana datasource queries
DynamoDB directly via the community plugin. Two datasources, but each
is used where it shines.

Timestream would have been a single answer, but it isn't available in
`eu-north-1` and the cross-region detour wasn't worth it.

## Migration order

1. **Stand up the new stack** — `bootstrap` then `environments/home`
   *(done)*
2. **Verify end-to-end** with `aws iot-data publish` → check DynamoDB
   *(done)*
3. **Switch the Pi** to the new MQTT publisher
   *(done — `pi/ruuvitag_publish.py` running under systemd)*
4. **Add `metrics-publisher` module** — Lambda + IoT Rule action that
   pushes each reading to Grafana Cloud's Prometheus `remote_write`
   endpoint. Credentials in Secrets Manager.
5. **Run both publishers in parallel** for ~2 weeks so we can compare
   numbers in the old Grafana vs the new one.
6. **Migrate historical data** — see below. Lands in a separate
   `ruuvitag-readings-historical-home` table.
7. **Wire up Grafana Cloud dashboards** — one Prometheus-backed live
   dashboard, one DynamoDB-backed archive dashboard. Both committed
   as JSON under `docs/grafana/`.
8. **Decommission the EC2** — final EBS snapshot to S3 Glacier Deep
   Archive (~$0.03/month for 30 GB), terminate, release the EIP, drop
   the `koti.atkpihlainen.fi` DNS record.

## Historical data migration

About 4.2 GB of TSM-compressed data spanning 2020-03 → 2026-04. Raw
record count likely 50-150M depending on the original publish cadence,
which is more granularity than any dashboard needs once it's a year
old.

The whole flow lives in three places:

- `environments/home/historical.tf` — migration S3 bucket + the
  archive DynamoDB table with an `import_table` block.
- `scripts/migrate_influx_to_s3.py` — runs on the EC2, downsamples
  and uploads the gzipped NDJSON.
- This document — the order in which to run them.

### Step by step

1. **Create the migration bucket** (Terraform won't try to create the
   archive table yet because it depends on data being in the bucket):
   ```sh
   cd environments/home
   terraform apply -target=aws_s3_bucket.migration \
                   -target=aws_s3_bucket_public_access_block.migration \
                   -target=aws_s3_bucket_server_side_encryption_configuration.migration \
                   -target=aws_s3_bucket_lifecycle_configuration.migration
   ```

2. **Run the export on the EC2**. The script downsamples
   `ruuvi_measurements` to a new `ruuvi_1m` measurement (1-minute
   means), then iterates month by month writing
   `ruuvi-YYYY-MM.ndjson.gz` files into the bucket. Names are
   normalised: `Terassi → Ulko`, `Eteinen → Sisä`.
   ```sh
   ssh user@legacy-ec2
   sudo apt-get install -y python3 awscli  # if not already
   export INFLUX_USER=ruuvi_user
   export INFLUX_PW='...'
   export S3_BUCKET=ruuvitag-migration-<account-id>
   python3 scripts/migrate_influx_to_s3.py
   ```
   ~12M rows total. The downsample runs once; the export takes
   roughly an hour on a t3.micro.

3. **Verify the upload**:
   ```sh
   aws s3 ls s3://$S3_BUCKET/historical/ --human-readable --summarize
   ```
   Expect ~75 monthly files, gzip total in the low hundreds of MB.

4. **Apply the historical table**. The `import_table` block on
   `aws_dynamodb_table.historical` triggers DynamoDB's S3 Import:
   ```sh
   cd environments/home
   terraform apply
   ```
   The apply waits for the import to complete. Cost: $0.15 / GB of
   source data, ~$0.30-0.50 for a gzipped export of 12M rows.

5. **Once the archive dashboard renders the full timeline**, the
   bucket auto-expires after 30 days (lifecycle rule). No manual
   cleanup needed.

## EC2 decommission

After ~2 weeks of parallel running and the historical import is in
Grafana:

```sh
# Final snapshot for posterity (rare incidents may want raw InfluxDB)
aws ec2 create-snapshot --volume-id vol-... \
  --description 'final ruuvi influx snapshot'

# Terminate
aws ec2 terminate-instances --instance-ids i-...
aws ec2 release-address --allocation-id eipalloc-...

# Route 53
aws route53 change-resource-record-sets ...  # delete koti.atkpihlainen.fi A
```

The legacy Terraform repo lives elsewhere — run `terraform destroy`
there once the snapshot is verified.

## Open questions

- Grafana Cloud Pro upgrade ($19/mo) gets 13 months of metrics
  retention. Probably overkill for a home project; the DynamoDB
  archive answers the same question for $0.50/mo.
- The historical NDJSON export is single-threaded on a t3.micro and
  might take an hour. Acceptable; this only runs once.
