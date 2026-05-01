# Backend configuration — values must be hardcoded here.
# Terraform parses the backend block before any variables, locals, or
# outputs from other files are evaluated.
#
# This file is added AFTER the initial `terraform apply` that created the
# bucket, table, and KMS key. After adding it, run:
#
#   terraform init -migrate-state
#
# to move the local state into the S3 bucket the bootstrap just provisioned.

terraform {
  backend "s3" {
    bucket         = "ruuvitag-serverless-tfstate-465118852707"
    key            = "bootstrap/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "ruuvitag-serverless-tflock"
    encrypt        = true
    kms_key_id     = "alias/ruuvitag-serverless-tfstate"
  }
}
