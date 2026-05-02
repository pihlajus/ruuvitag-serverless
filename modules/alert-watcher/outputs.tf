output "function_name" {
  description = "Name of the alert-watcher Lambda."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the alert-watcher Lambda."
  value       = aws_lambda_function.this.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic the watcher publishes to."
  value       = aws_sns_topic.alerts.arn
}

output "schedule_rule_arn" {
  description = "ARN of the EventBridge rule."
  value       = aws_cloudwatch_event_rule.schedule.arn
}
