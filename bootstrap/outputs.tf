output "state_bucket_name" {
  description = "S3 bucket holding Terraform state files. Used in environments/*/backend.tf."
  value       = aws_s3_bucket.state.id
}

output "state_lock_table_name" {
  description = "DynamoDB table for state locking. Used in environments/*/backend.tf."
  value       = aws_dynamodb_table.lock.name
}

output "state_kms_key_arn" {
  description = "KMS key ARN that encrypts state at rest."
  value       = aws_kms_key.state.arn
}

output "state_kms_key_alias" {
  description = "Human-friendly KMS alias for the state encryption key."
  value       = aws_kms_alias.state.name
}

output "aws_region" {
  description = "Region where the backend lives. Environments must use the same region."
  value       = var.aws_region
}
