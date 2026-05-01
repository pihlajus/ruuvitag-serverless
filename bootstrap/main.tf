terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}

# Look up the current account ID so the bucket name is account-scoped
# without hardcoding it in source.
data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  lock_table_name   = "${var.project}-tflock"
  kms_alias         = "alias/${var.project}-tfstate"
}

# ------------------------------------------------------------------------
# KMS key for encrypting Terraform state at rest
# ------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform state files for ${var.project}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "state" {
  name          = local.kms_alias
  target_key_id = aws_kms_key.state.key_id
}

# ------------------------------------------------------------------------
# S3 bucket for Terraform state
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # This bucket is critical to the lifecycle of all environments —
  # `force_destroy = false` is a deliberate safeguard against accidents.
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------
# DynamoDB table for state locking
# ------------------------------------------------------------------------

resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
