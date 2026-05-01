# Module: timeseries-storage

DynamoDB table for time-stamped sensor readings, plus the IAM role the
IoT Rules engine uses to write into it.

## Why DynamoDB instead of Timestream

Timestream would be the textbook answer, but it is not available in
`eu-north-1` (Stockholm) where the rest of this stack lives. DynamoDB
on-demand is a fine substitute at this volume:

| Volume | DynamoDB cost |
|---|---|
| 4 sensors × 1 reading / minute | ~$0.20 / month writes + storage |

Queries by `mac` + time range are efficient: GetItem / Query on the
composite key.

## Schema

| Attribute | Type | Role |
|---|---|---|
| `mac` | S | Partition key — sensor MAC |
| `ts_ms` | N | Sort key — millisecond epoch timestamp |
| `ttl` | N | Optional epoch-seconds expiry (set by writer; module enables TTL on this attr) |
| `temperature`, `humidity`, `pressure`, `battery`, ... | N | Whatever the message includes; DynamoDB is schemaless beyond keys |

Point-in-time recovery (PITR) is enabled.

## Inputs

| Name | Type | Default |
|---|---|---|
| `env` | string | (required) |
| `table_name` | string | `ruuvitag-readings` |
| `partition_key` | string | `mac` |
| `sort_key` | string | `ts_ms` |
| `ttl_attribute` | string | `ttl` (set to `""` to disable TTL) |

## Outputs

| Name | Description |
|---|---|
| `table_name` | Table name (with env suffix) |
| `table_arn` | Table ARN |
| `iot_write_role_arn` | IAM role for the IoT Rule |
| `partition_key` | For the consumer to pass into the IoT Rule SQL |
| `sort_key` | Same |
