locals {
  function_name = "ruuvitag-metrics-publisher-${var.env}"
}

# ----------------------------------------------------------------------
# Lambda package — single-file zip from src/lambda_function.py.
# ----------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/build/lambda.zip"
}

# ----------------------------------------------------------------------
# Execution role — only needs CloudWatch Logs.
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

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

# ----------------------------------------------------------------------
# Function. The Grafana credentials live in environment variables —
# encrypted at rest with the Lambda service KMS key. For a home stack
# Secrets Manager would add cost ($0.40/secret/month) without buying
# anything meaningful here.
# ----------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda.output_path

  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      NAME_LOOKUP      = jsonencode(var.name_lookup)
      GRAFANA_URL      = var.grafana_url
      GRAFANA_USERNAME = var.grafana_username
      GRAFANA_API_KEY  = var.grafana_api_key
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]
}

# ----------------------------------------------------------------------
# IoT Topic Rule that fans the same MQTT messages out to this Lambda.
# Separate rule from the DynamoDB one so a Lambda failure can't block
# the archive write.
# ----------------------------------------------------------------------

resource "aws_iot_topic_rule" "to_grafana" {
  name        = "ruuvitag_to_grafana_${var.env}"
  description = "Forward Ruuvitag readings to Grafana Cloud Mimir via the metrics-publisher Lambda."
  enabled     = true
  sql         = "SELECT * FROM '${var.topic_filter}'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.this.arn
  }

  error_action {
    cloudwatch_logs {
      log_group_name = aws_cloudwatch_log_group.rule_errors.name
      role_arn       = aws_iam_role.iot_rule_logs.arn
    }
  }
}

resource "aws_lambda_permission" "iot_invoke" {
  statement_id  = "AllowIoTRuleInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.to_grafana.arn
}

# ----------------------------------------------------------------------
# IoT Rule error sink — same pattern as in environments/home/main.tf.
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rule_errors" {
  name              = "/aws/iot/ruuvitag_to_grafana_${var.env}"
  retention_in_days = 14
}

resource "aws_iam_role" "iot_rule_logs" {
  name = "ruuvitag-iot-rule-logs-grafana-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "iot_rule_logs" {
  role = aws_iam_role.iot_rule_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.rule_errors.arn}:*"
    }]
  })
}
