# Archive table populated once from the legacy InfluxDB via S3 Import.
#
# Schema differs from the live table on purpose: this one is keyed on
# the human-readable sensor name (Ulko / Sisä / Sauna). MAC addresses
# don't survive into the dashboards — and the legacy data uses
# different MACs anyway as sensors got swapped over the years.
#
# Workflow:
#   1. terraform apply -target=aws_s3_bucket.migration
#      (creates the bucket, but not the table)
#   2. INFLUX_USER=... INFLUX_PW=... S3_BUCKET=ruuvitag-migration-...
#      python3 scripts/migrate_influx_to_s3.py
#      (uploads gzipped NDJSON to the bucket)
#   3. terraform apply
#      (creates the historical table by triggering S3 Import on the
#      uploaded NDJSON; takes minutes for ~12M rows)
#
# After step 3 the import_table block is frozen via ignore_changes so
# subsequent applies don't try to re-import.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "migration" {
  bucket = "ruuvitag-migration-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "migration" {
  bucket                  = aws_s3_bucket.migration.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "migration" {
  bucket = aws_s3_bucket.migration.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "migration" {
  bucket = aws_s3_bucket.migration.id
  rule {
    id     = "expire-export-after-import"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

resource "aws_dynamodb_table" "historical" {
  name         = "ruuvitag-readings-historical-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"
  range_key    = "ts_ms"

  attribute {
    name = "name"
    type = "S"
  }
  attribute {
    name = "ts_ms"
    type = "N"
  }

  import_table {
    input_format           = "DYNAMODB_JSON"
    input_compression_type = "GZIP"
    s3_bucket_source {
      bucket     = aws_s3_bucket.migration.bucket
      key_prefix = "historical/"
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [import_table]
  }
}

output "migration_bucket" {
  description = "S3 bucket holding the gzipped NDJSON export for the historical import."
  value       = aws_s3_bucket.migration.bucket
}

output "historical_table_name" {
  description = "DynamoDB table holding the imported historical readings."
  value       = aws_dynamodb_table.historical.name
}
