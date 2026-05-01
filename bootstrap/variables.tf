variable "aws_region" {
  description = "AWS region where the state backend lives. All environments use the same region for the backend."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name used as a prefix in resource names."
  type        = string
  default     = "ruuvitag-serverless"
}
