terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Look up the account ID and the IoT Data endpoint at apply time.
# Account ID goes into IAM/IoT policy ARNs; endpoint is returned as
# an output so the device knows where to connect.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iot_endpoint" "data_ats" {
  endpoint_type = "iot:Data-ATS"
}

locals {
  full_name      = "${var.thing_name}-${var.env}"
  client_id      = local.full_name
  topic_resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.mqtt_topic_prefix}/*"
  client_resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/${local.client_id}"
}

# ------------------------------------------------------------------------
# IoT Thing — logical device record
# ------------------------------------------------------------------------

resource "aws_iot_thing" "device" {
  name = local.full_name

  # IoT Thing attributes have a restrictive regex (no spaces).
  # Keep this minimal — descriptive text lives in tags on the policy
  # and in module documentation, not in the Thing record.
  attributes = {
    env = var.env
  }
}

# ------------------------------------------------------------------------
# X.509 certificate — AWS generates the keypair, we capture both pieces
# in outputs (sensitive) so the operator can write them to the device.
# ------------------------------------------------------------------------

resource "aws_iot_certificate" "device" {
  active = true
}

# ------------------------------------------------------------------------
# IoT policy — what the device is allowed to do.
#
# - Connect only with this exact client ID (prevents the cert being
#   stolen and used by a device claiming a different identity).
# - Publish only to topics under the configured prefix.
# ------------------------------------------------------------------------

resource "aws_iot_policy" "device" {
  name = "${local.full_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = local.client_resource
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Publish"]
        Resource = local.topic_resource
      },
    ]
  })
}

# ------------------------------------------------------------------------
# Bindings: cert ↔ Thing, cert ↔ policy
# ------------------------------------------------------------------------

resource "aws_iot_thing_principal_attachment" "device" {
  thing     = aws_iot_thing.device.name
  principal = aws_iot_certificate.device.arn
}

resource "aws_iot_policy_attachment" "device" {
  policy = aws_iot_policy.device.name
  target = aws_iot_certificate.device.arn
}
