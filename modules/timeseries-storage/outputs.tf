output "table_name" {
  description = "DynamoDB table name where IoT Rule writes sensor readings."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "DynamoDB table ARN."
  value       = aws_dynamodb_table.this.arn
}

output "iot_write_role_arn" {
  description = "IAM role the IoT Rules engine assumes to write into the table."
  value       = aws_iam_role.iot_rule_write.arn
}

output "partition_key" {
  description = "Partition key attribute name. Match this in the IoT Rule SQL."
  value       = var.partition_key
}

output "sort_key" {
  description = "Sort key attribute name. Match this in the IoT Rule SQL."
  value       = var.sort_key
}
