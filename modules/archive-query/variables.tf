variable "env" {
  description = "Environment name. Suffix in resource names."
  type        = string
}

variable "archive_table_name" {
  description = "Name of the historical readings DynamoDB table."
  type        = string
}

variable "archive_table_arn" {
  description = "ARN of the historical readings DynamoDB table."
  type        = string
}

variable "shared_secret" {
  description = "Bearer token expected in the X-Auth-Token header. Leave empty to disable auth (only for local testing)."
  type        = string
  sensitive   = true
}

variable "max_points" {
  description = "Maximum number of (ts, value) rows returned per query. Larger queries are decimated evenly."
  type        = number
  default     = 5000
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention for the archive-query Lambda."
  type        = number
  default     = 14
}
