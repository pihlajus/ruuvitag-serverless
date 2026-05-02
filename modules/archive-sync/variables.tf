variable "env" {
  description = "Environment name. Suffix in resource names."
  type        = string
}

variable "live_table_name" {
  description = "Name of the live readings DynamoDB table (mac, ts_ms)."
  type        = string
}

variable "live_table_arn" {
  description = "ARN of the live readings DynamoDB table."
  type        = string
}

variable "archive_table_name" {
  description = "Name of the historical readings DynamoDB table (name, ts_ms)."
  type        = string
}

variable "archive_table_arn" {
  description = "ARN of the historical readings DynamoDB table."
  type        = string
}

variable "name_lookup" {
  description = "Map of MAC (uppercase, no colons) to human-readable sensor name. Same shape as the metrics-publisher module."
  type        = map(string)
}

variable "schedule_expression" {
  description = "EventBridge schedule for the daily sync. Default: 03:00 UTC every day."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention for the archive-sync Lambda."
  type        = number
  default     = 14
}
