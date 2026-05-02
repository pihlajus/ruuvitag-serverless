variable "env" {
  description = "Environment name. Suffix in resource names."
  type        = string
}

variable "topic_filter" {
  description = "MQTT topic filter the IoT Rule subscribes to."
  type        = string
  default     = "ruuvitag/+/sensor"
}

variable "name_lookup" {
  description = "Map of MAC address (uppercase, no colons) to human-readable sensor name."
  type        = map(string)
}

variable "grafana_url" {
  description = "Grafana Cloud InfluxDB line-protocol push endpoint, e.g. https://<stack>.grafana.net/api/v1/push/influx/write"
  type        = string
}

variable "grafana_username" {
  description = "Grafana Cloud Metrics instance ID (numeric string)."
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana Cloud API key with metrics:write scope."
  type        = string
  sensitive   = true
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention for the Lambda."
  type        = number
  default     = 14
}
