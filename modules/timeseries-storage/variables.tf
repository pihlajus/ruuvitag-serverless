variable "env" {
  description = "Environment name, used in resource naming."
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name. Will get the env suffix appended."
  type        = string
  default     = "ruuvitag-readings"
}

variable "partition_key" {
  description = "Partition key — MAC address of the sensor that produced the reading."
  type        = string
  default     = "mac"
}

variable "sort_key" {
  description = "Sort key — millisecond timestamp of the reading."
  type        = string
  default     = "ts_ms"
}

variable "ttl_attribute" {
  description = "Name of the TTL attribute. Items with this attribute (epoch seconds) get evicted past expiry. Set to empty string to disable TTL."
  type        = string
  default     = "ttl"
}
