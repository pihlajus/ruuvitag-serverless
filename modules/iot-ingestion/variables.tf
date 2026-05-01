variable "env" {
  description = "Environment name, used as a suffix in resource names (e.g. 'home', 'prod')."
  type        = string
}

variable "thing_name" {
  description = "Logical name of the IoT Thing (the device that connects). Resource names are derived from this + env."
  type        = string
}

variable "mqtt_topic_prefix" {
  description = "MQTT topic prefix the device is allowed to publish under. The device can publish to <prefix>/* — anything beneath."
  type        = string
  default     = "ruuvitag"
}

variable "description" {
  description = "Human-readable description for the IoT Thing and policy."
  type        = string
  default     = "Ruuvitag bridge device publishing sensor telemetry over MQTT."
}
