output "function_name" {
  description = "Name of the archive-query Lambda."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the archive-query Lambda."
  value       = aws_lambda_function.this.arn
}

output "function_url" {
  description = "Public Function URL — point Grafana Infinity datasource at this with the X-Auth-Token header."
  value       = aws_lambda_function_url.this.function_url
}

output "log_group_name" {
  description = "CloudWatch log group for the Lambda."
  value       = aws_cloudwatch_log_group.lambda.name
}
