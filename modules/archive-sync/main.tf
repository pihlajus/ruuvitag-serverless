locals {
  function_name = "ruuvitag-archive-sync-${var.env}"
}

# ----------------------------------------------------------------------
# Lambda package
# ----------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/build/lambda.zip"
}

# ----------------------------------------------------------------------
# Execution role: Query on live, BatchWrite on archive, plus logs.
# ----------------------------------------------------------------------

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

resource "aws_iam_role_policy" "ddb" {
  name = "ddb-live-read-archive-write"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:DescribeTable",
        ]
        Resource = var.live_table_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:DescribeTable",
        ]
        Resource = var.archive_table_arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

# ----------------------------------------------------------------------
# Function — invoked daily by EventBridge.
# Memory at 512 MB to make BatchWriteItem throughput respectable;
# timeout at 5 min covers up to ~10k items per sensor (well above the
# 1440 we expect for one day at 1-min cadence).
# ----------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda.output_path

  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512

  environment {
    variables = {
      LIVE_TABLE_NAME    = var.live_table_name
      ARCHIVE_TABLE_NAME = var.archive_table_name
      NAME_LOOKUP        = jsonencode(var.name_lookup)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.ddb,
    aws_cloudwatch_log_group.lambda,
  ]
}

# ----------------------------------------------------------------------
# EventBridge schedule
# ----------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${local.function_name}-daily"
  description         = "Trigger archive-sync once per day."
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.daily.name
  target_id = "lambda"
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}
