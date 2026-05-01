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
