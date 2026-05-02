locals {
  function_name = "ruuvitag-archive-query-${var.env}"
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
# Execution role — least-privilege Query on the archive table only.
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

resource "aws_iam_role_policy" "dynamodb_read" {
  name = "dynamodb-query-archive"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:Query",
        "dynamodb:DescribeTable",
      ]
      Resource = var.archive_table_arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

# ----------------------------------------------------------------------
# Function + public Function URL.
#
# Auth on the URL itself is NONE — Grafana's Infinity datasource doesn't
# easily do AWS sigv4 against Lambda Function URLs. Instead the function
# checks an X-Auth-Token header against a shared secret. The URL is
# random per function, but treating the bearer token as a real secret
# is the right thing.
# ----------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda.output_path

  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ARCHIVE_TABLE_NAME = var.archive_table_name
      SHARED_SECRET      = var.shared_secret
      MAX_POINTS         = tostring(var.max_points)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.dynamodb_read,
    aws_cloudwatch_log_group.lambda,
  ]
}

resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET"]
    allow_headers     = ["x-auth-token", "content-type"]
    max_age           = 86400
  }
}
