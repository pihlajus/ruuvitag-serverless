# Pass through the module outputs the operator needs.
# Sensitive outputs propagate the sensitive flag automatically.

output "thing_name" {
  description = "Full IoT Thing name. Use as MQTT client_id on the device."
  value       = module.iot_ingestion.thing_name
}

output "iot_endpoint" {
  description = "MQTT endpoint the device connects to."
  value       = module.iot_ingestion.iot_endpoint
}

output "certificate_pem" {
  description = "X.509 certificate. Read with: terraform output -raw certificate_pem > cert.pem"
  value       = module.iot_ingestion.certificate_pem
  sensitive   = true
}

output "private_key" {
  description = "Private key. Read with: terraform output -raw private_key > private.key"
  value       = module.iot_ingestion.private_key
  sensitive   = true
}

output "dynamodb_table" {
  description = "DynamoDB table where sensor readings land. Use in Grafana datasource config."
  value       = module.timeseries.table_name
}

output "iot_rule_name" {
  description = "Name of the IoT topic rule that routes MQTT to DynamoDB."
  value       = aws_iot_topic_rule.ruuvitag_to_dynamodb.name
}
