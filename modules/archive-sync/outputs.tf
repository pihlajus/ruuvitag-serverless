output "function_name" {
  description = "Name of the archive-sync Lambda."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the archive-sync Lambda."
  value       = aws_lambda_function.this.arn
}

output "schedule_rule_arn" {
  description = "ARN of the EventBridge rule that triggers the daily sync."
  value       = aws_cloudwatch_event_rule.daily.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the Lambda."
  value       = aws_cloudwatch_log_group.lambda.name
}
