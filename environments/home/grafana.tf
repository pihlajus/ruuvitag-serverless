# ------------------------------------------------------------------------
# Grafana dashboards — push the JSON in docs/grafana/ into the Grafana
# stack on terraform apply. The JSON is the source of truth; UI edits get
# clobbered on the next apply, by design.
#
# The exported JSON contains a ${DS_PROMETHEUS} input placeholder. We
# resolve it at apply time by looking up the Prometheus datasource by
# name and substituting its UID into the rendered JSON.
# ------------------------------------------------------------------------

provider "grafana" {
  url  = var.grafana_stack_url
  auth = var.grafana_dashboard_token
}

data "grafana_data_source" "prometheus" {
  name = var.grafana_prometheus_ds_name
}

locals {
  live_dashboard_raw = jsondecode(file("${path.module}/../../docs/grafana/ruuvitag-live.json"))

  # Strip exporter-only fields; grafana_dashboard manages id/version itself.
  live_dashboard_clean = {
    for k, v in local.live_dashboard_raw : k => v
    if !contains(["__inputs", "__requires", "id", "version"], k)
  }

  live_dashboard_json = replace(
    jsonencode(local.live_dashboard_clean),
    "$${DS_PROMETHEUS}",
    data.grafana_data_source.prometheus.uid,
  )
}

resource "grafana_dashboard" "live" {
  config_json = local.live_dashboard_json
  overwrite   = true
}

output "grafana_live_dashboard_url" {
  description = "URL to the imported live dashboard."
  value       = grafana_dashboard.live.url
}
