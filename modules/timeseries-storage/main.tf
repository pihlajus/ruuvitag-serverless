terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  full_table_name = "${var.table_name}-${var.env}"
}

# ------------------------------------------------------------------------
# DynamoDB table for sensor readings.
#
# Originally planned as Timestream, but Timestream is not available in
# eu-north-1 (Stockholm). DynamoDB on-demand fits this volume cheaply
# (~$0.20/month for 4 sensors at 1-minute interval) and stays in-region.
#
# Schema:
#   mac (S)    — partition key, sensor MAC
#   ts_ms (N)  — sort key, millisecond timestamp
#   ttl (N)    — optional epoch-seconds expiry (set by writer)
#   <measures> — temperature, humidity, pressure, battery, ...
#
# Queries by mac + time range are efficient: GetItem / Query.
# ------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.full_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = var.partition_key
  range_key = var.sort_key

  attribute {
    name = var.partition_key
    type = "S"
  }

  attribute {
    name = var.sort_key
    type = "N"
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute == "" ? [] : [1]
    content {
      attribute_name = var.ttl_attribute
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ------------------------------------------------------------------------
# IAM role assumed by the IoT Rules engine when writing to this table.
# ------------------------------------------------------------------------

resource "aws_iam_role" "iot_rule_write" {
  name = "${local.full_table_name}-iot-write"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "iot_rule_write" {
  name = "${local.full_table_name}-iot-write"
  role = aws_iam_role.iot_rule_write.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
      ]
      Resource = aws_dynamodb_table.this.arn
    }]
  })
}
