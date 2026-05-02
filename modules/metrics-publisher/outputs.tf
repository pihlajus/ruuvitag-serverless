output "function_arn" {
  description = "ARN of the metrics-publisher Lambda."
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Name of the metrics-publisher Lambda."
  value       = aws_lambda_function.this.function_name
}

output "rule_arn" {
  description = "ARN of the IoT Topic Rule that triggers the Lambda."
  value       = aws_iot_topic_rule.to_grafana.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the Lambda."
  value       = aws_cloudwatch_log_group.lambda.name
}
