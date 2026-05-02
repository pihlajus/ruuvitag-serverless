variable "aws_region" {
  description = "AWS region. Must match the region of the bootstrap state backend."
  type        = string
  default     = "eu-north-1"
}

variable "env" {
  description = "Environment name. Suffix in resource names."
  type        = string
  default     = "home"
}

variable "thing_name" {
  description = "Logical name of the Pi acting as the Ruuvitag bridge."
  type        = string
  default     = "ruuvitag-pi"
}

# ------------------------------------------------------------------------
# Grafana Cloud — used by the metrics-publisher Lambda. Keep these in
# terraform.tfvars (gitignored) or pass via TF_VAR_* env vars.
# ------------------------------------------------------------------------

variable "name_lookup" {
  description = "MAC (uppercase, no colons) → human-readable sensor name."
  type        = map(string)
  default = {
    "F2FD824D5C5C" = "Ulko"
    "CB02684A18A0" = "Sisä"
    "FD7DDF1990F8" = "Sauna"
  }
}

variable "grafana_url" {
  description = "Grafana Cloud InfluxDB line-protocol push URL. Leave empty until the Grafana Cloud stack exists; the metrics-publisher Lambda will deploy with a placeholder and fail to push at runtime, which is fine until you swap real credentials in."
  type        = string
  default     = ""
}

variable "grafana_username" {
  description = "Grafana Cloud Metrics instance ID (numeric string)."
  type        = string
  default     = ""
}

variable "grafana_api_key" {
  description = "Grafana Cloud API key with metrics:write scope."
  type        = string
  sensitive   = true
  default     = ""
}

variable "archive_query_secret" {
  description = "Bearer token Grafana sends in X-Auth-Token to the archive-query Lambda. Generate with `openssl rand -hex 32` and put in terraform.tfvars."
  type        = string
  sensitive   = true
  default     = ""
}
