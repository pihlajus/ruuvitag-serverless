variable "env" {
  description = "Environment name. Suffix in resource names."
  type        = string
}

variable "live_table_name" {
  description = "Name of the live readings DynamoDB table."
  type        = string
}

variable "live_table_arn" {
  description = "ARN of the live readings DynamoDB table."
  type        = string
}

variable "name_lookup" {
  description = "Map of MAC (uppercase, no colons) to human-readable sensor name."
  type        = map(string)
}

variable "alert_email" {
  description = "Email address to receive sensor-silent alerts. AWS sends a confirmation link the first time."
  type        = string
}

variable "threshold_minutes" {
  description = "Sensor is considered silent after this many minutes since the last reading."
  type        = number
  default     = 60
}

variable "cooldown_hours" {
  description = "After alerting about a stale sensor, suppress further emails about that same sensor for this many hours. State is cleared when the sensor recovers, so a new outage triggers immediately."
  type        = number
  default     = 24
}

variable "schedule_expression" {
  description = "EventBridge schedule for the watcher. Default: top of every hour."
  type        = string
  default     = "cron(0 * * * ? *)"
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention for the alert-watcher Lambda."
  type        = number
  default     = 14
}
