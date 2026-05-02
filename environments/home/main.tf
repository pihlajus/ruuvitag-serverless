terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ruuvitag-serverless"
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

# ------------------------------------------------------------------------
# Storage first — the IoT Rule below needs the table ARN + write role.
# ------------------------------------------------------------------------

module "timeseries" {
  source = "../../modules/timeseries-storage"

  env        = var.env
  table_name = "ruuvitag-readings"
}

# ------------------------------------------------------------------------
# Device side: Thing, certificate, policy.
# ------------------------------------------------------------------------

module "iot_ingestion" {
  source = "../../modules/iot-ingestion"

  env               = var.env
  thing_name        = var.thing_name
  mqtt_topic_prefix = "ruuvitag"
}

# ------------------------------------------------------------------------
# IoT Rule that wires the device's MQTT topic into the DynamoDB table.
#
# The rule lives in the environment composition, not in either module —
# it is the contract between them. Either module can be reused on its
# own without dragging in the other.
#
# The dynamodbv2 action puts the entire SELECT result as a single item.
# The MQTT payload's keys (mac, ts_ms, temperature, ...) become item
# attributes. mac is the partition key, ts_ms the sort key.
# ------------------------------------------------------------------------

resource "aws_iot_topic_rule" "ruuvitag_to_dynamodb" {
  name        = "ruuvitag_to_dynamodb_${var.env}"
  description = "Route Ruuvitag sensor readings from MQTT into DynamoDB."
  enabled     = true
  sql         = "SELECT * FROM 'ruuvitag/+/sensor'"
  sql_version = "2016-03-23"

  dynamodbv2 {
    role_arn = module.timeseries.iot_write_role_arn

    put_item {
      table_name = module.timeseries.table_name
    }
  }

  error_action {
    cloudwatch_logs {
      log_group_name = aws_cloudwatch_log_group.iot_rule_errors.name
      role_arn       = aws_iam_role.iot_rule_logs.arn
    }
  }
}

# ------------------------------------------------------------------------
# Error sink: when the IoT Rule fails (e.g. malformed payload, throttling)
# the message is logged to CloudWatch instead of being dropped silently.
# ------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "iot_rule_errors" {
  name              = "/aws/iot/rule/ruuvitag_to_dynamodb_${var.env}/errors"
  retention_in_days = 14
}

resource "aws_iam_role" "iot_rule_logs" {
  name = "ruuvitag-${var.env}-iot-rule-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "iot_rule_logs" {
  name = "write-iot-rule-error-logs"
  role = aws_iam_role.iot_rule_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.iot_rule_errors.arn}:*"
    }]
  })
}

# ------------------------------------------------------------------------
# Metrics fan-out — second IoT Rule action that pushes each reading to
# Grafana Cloud Mimir as a Prometheus-style metric. The DynamoDB rule
# above is independent: a Lambda failure won't keep readings out of the
# archive.
# ------------------------------------------------------------------------

module "metrics_publisher" {
  source = "../../modules/metrics-publisher"

  env          = var.env
  topic_filter = "ruuvitag/+/sensor"
  name_lookup  = var.name_lookup

  grafana_url      = var.grafana_url
  grafana_username = var.grafana_username
  grafana_api_key  = var.grafana_api_key
}

# ------------------------------------------------------------------------
# HTTP query proxy in front of the archive table — turns the historical
# DynamoDB readings into a JSON time-series consumable by the Grafana
# Infinity datasource. Keeps the dashboard side decoupled from DynamoDB
# specifics; the Lambda is the only thing that knows the table schema.
# ------------------------------------------------------------------------

module "archive_query" {
  source = "../../modules/archive-query"

  env                = var.env
  archive_table_name = aws_dynamodb_table.historical.name
  archive_table_arn  = aws_dynamodb_table.historical.arn
  shared_secret      = var.archive_query_secret
}

output "archive_query_url" {
  description = "Function URL for the archive-query Lambda."
  value       = module.archive_query.function_url
}
