output "thing_name" {
  description = "Full IoT Thing name (with env suffix). Use as the MQTT client_id."
  value       = aws_iot_thing.device.name
}

output "thing_arn" {
  description = "ARN of the IoT Thing."
  value       = aws_iot_thing.device.arn
}

output "iot_endpoint" {
  description = "MQTT/HTTPS endpoint the device connects to."
  value       = data.aws_iot_endpoint.data_ats.endpoint_address
}

output "certificate_arn" {
  description = "ARN of the X.509 certificate. Used by IoT Rules and audit tooling."
  value       = aws_iot_certificate.device.arn
}

output "certificate_pem" {
  description = "X.509 certificate PEM. Write to the device. Public information — not sensitive — but kept separate from the rest of the outputs to make handling easier."
  value       = aws_iot_certificate.device.certificate_pem
  sensitive   = true
}

output "private_key" {
  description = "Private key PEM corresponding to the certificate. SENSITIVE — write to the device, never commit, never log."
  value       = aws_iot_certificate.device.private_key
  sensitive   = true
}

output "public_key" {
  description = "Public key PEM. Provided for completeness; not normally needed by the device."
  value       = aws_iot_certificate.device.public_key
  sensitive   = true
}
