# Grafana dashboards

Two dashboards, one per datasource. The live one is the daily-driver
view; the archive one is for the long historical timeline.

## Files

- `ruuvitag-live.json` — Prometheus-backed dashboard. Last 14 days
  (Grafana Cloud Free tier retention). Imported into Grafana Cloud.
- `ruuvitag-archive.queries.md` — query snippets for the historical
  DynamoDB table. The actual JSON depends on which DynamoDB plugin
  ends up installed; see notes below.

## Import the live dashboard

1. In Grafana Cloud: **Dashboards → Import → Upload JSON file**
2. Pick `ruuvitag-live.json`
3. Map the `DS_PROMETHEUS` input to your Grafana Cloud Prometheus
   datasource (it's there by default — `grafanacloud-<stack>-prom`)
4. Save

The dashboard expects metrics named `ruuvi_temperature`,
`ruuvi_humidity`, `ruuvi_pressure`, `ruuvi_dew_point`,
`ruuvi_air_density` with a `name` label of `Ulko` / `Sisä` / `Sauna`.
Those names are produced by the `metrics-publisher` Lambda — see the
module's MAC→name lookup config.

## Datasource for the archive dashboard

The official Grafana DynamoDB datasource is Enterprise-only — not
available on the Free tier. Instead, the `archive-query` Lambda
module exposes a tiny HTTP shim in front of the historical table,
and the dashboard queries it through the **Infinity** community
plugin (free).

### Install Infinity plugin

1. Connections → **Add new connection** → search **"Infinity"**
2. Click **"Install"** on `Infinity` by `yesoreyeram`
3. After install, click **"Add new data source"**

### Configure the datasource

- Name: `Ruuvitag archive`
- URL: paste the Function URL from `terraform output archive_query_url`,
  e.g. `https://kkdpvza3nh7t7tu3yaqcnux7ra0alylh.lambda-url.eu-north-1.on.aws/`
- Authentication: **No Auth**
- Custom HTTP Headers (Add header):
  - Header: `X-Auth-Token`
  - Value: the `archive_query_secret` from `terraform.tfvars`
- Allowed Hosts: same Function URL as above (paste it again)
- Save & test

### Import the archive dashboard

1. Dashboards → **New** → **Import** → upload
   `ruuvitag-archive.json`
2. Map `DS_INFINITY` to your `Ruuvitag archive` data source
3. Time range: defaults to last 30 d. Stretch out as needed — the
   archive covers 2020-03 onward.

### How it works

Each panel queries the Lambda Function URL with `?sensor=X&field=Y&from=$__from&to=$__to`.
The Lambda authenticates the bearer token, queries the historical
DynamoDB table, decimates to at most 5000 points, and returns a JSON
array `[{"ts": ..., "v": ...}, ...]` that Infinity parses into a
Grafana time-series.

## InfluxQL → PromQL conversion table

The original Grafana on the EC2 used InfluxQL. These are the per-panel
mappings used in `ruuvitag-live.json`. Same shape works for any new
panels you'd add later.

| Original InfluxQL                                                   | PromQL                                                            |
|---------------------------------------------------------------------|-------------------------------------------------------------------|
| `SELECT last("temperature") WHERE "name"='X'`                       | `ruuvi_temperature{name="X"}`                                     |
| `SELECT last("humidity") WHERE "name"='X'`                          | `ruuvi_humidity{name="X"}`                                        |
| `SELECT last("pressure") / 100 WHERE "name"='X'`                    | `ruuvi_pressure{name="X"} / 100`                                  |
| `SELECT mean("temperature") GROUP BY time($__interval)`             | `avg_over_time(ruuvi_temperature{name="X"}[$__interval])`         |
| `SELECT max("temperature") GROUP BY time($__interval)`              | `max_over_time(ruuvi_temperature{name="X"}[$__interval])`         |
| `SELECT min("temperature") GROUP BY time($__interval)`              | `min_over_time(ruuvi_temperature{name="X"}[$__interval])`         |
| `SELECT max("temperature") GROUP BY time(24h)`                      | `max_over_time(ruuvi_temperature{name="X"}[24h])`                 |
| `count(...) WHERE temperature > 50 GROUP BY time(18h)` (sauna)      | `count_over_time((ruuvi_temperature{name="Sauna"} > 50)[$__range:1h])` |
| `SELECT max("temperature")` (no time filter — all-time max)         | not possible in Prometheus past retention; see archive dashboard  |

## Sensor renames

Old InfluxDB tags vs new Prometheus labels:

| Old `name` tag | New `name` label |
|---|---|
| `Terassi`      | `Ulko`           |
| `Eteinen`      | `Sisä`           |
| `Sauna`        | `Sauna`          |

The downsample/export script applies the same rename, so the archive
table is also keyed on `Ulko` / `Sisä` / `Sauna`. No MAC addresses
escape into the dashboard layer.
