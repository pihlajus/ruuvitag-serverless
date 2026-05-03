locals {
  function_name = "ruuvitag-alert-watcher-${var.env}"
}

# ----------------------------------------------------------------------
# SNS topic + email subscription
#
# AWS sends a confirmation email the first time the subscription is
# created. Click the link in that email; until you do, no alerts get
# delivered. The topic itself accepts publishes from day one.
# ----------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.function_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # Email subscriptions go through a confirmation flow; Terraform
  # treats them as "pending confirmation" until the user clicks the
  # link. Without this, plan/apply would loop on the unconfirmed state.
  confirmation_timeout_in_minutes = 1
  endpoint_auto_confirms          = false
}

# ----------------------------------------------------------------------
# Lambda package + execution role
# ----------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.function_name}-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ddb_query" {
  name = "ddb-live-read"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:Query",
        "dynamodb:DescribeTable",
      ]
      Resource = var.live_table_arn
    }]
  })
}

resource "aws_iam_role_policy" "sns_publish" {
  name = "sns-publish-alerts"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}

# ----------------------------------------------------------------------
# Per-sensor alert cooldown state.
#
# JSON map: sensor name → unix-ms of the last alert email. Lambda reads
# at the start of each run, and writes back when the set of stale
# sensors changes. Standard SSM parameters are free, so this is the
# cheapest place to keep one row of mutable state.
#
# ignore_changes on value: the Lambda is the writer; terraform only
# seeds an empty map on first apply.
# ----------------------------------------------------------------------

resource "aws_ssm_parameter" "alert_state" {
  name        = "/ruuvitag-${var.env}/alert-state"
  description = "Per-sensor cooldown state for the alert-watcher Lambda."
  type        = "String"
  value       = "{}"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role_policy" "ssm_state" {
  name = "ssm-alert-state"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:PutParameter",
      ]
      Resource = aws_ssm_parameter.alert_state.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

# ----------------------------------------------------------------------
# Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda.output_path

  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      LIVE_TABLE_NAME   = var.live_table_name
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
      NAME_LOOKUP       = jsonencode(var.name_lookup)
      THRESHOLD_MINUTES = tostring(var.threshold_minutes)
      ALERT_STATE_PARAM = aws_ssm_parameter.alert_state.name
      COOLDOWN_HOURS    = tostring(var.cooldown_hours)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.ddb_query,
    aws_iam_role_policy.sns_publish,
    aws_iam_role_policy.ssm_state,
    aws_cloudwatch_log_group.lambda,
  ]
}

# ----------------------------------------------------------------------
# EventBridge schedule
# ----------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.function_name}-schedule"
  description         = "Trigger alert-watcher on a schedule."
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
