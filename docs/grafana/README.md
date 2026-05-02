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

DynamoDB doesn't have a single canonical Grafana datasource. Three
realistic choices:

| Plugin | Query style | Comment |
|---|---|---|
| `grafana-dynamodb-datasource` (community) | JSON KeyCondition | Lightweight, no extra services. PartiQL also supported. |
| `grafana-athena-datasource` (official AWS) | SQL via Athena Federated Query | Familiar SQL, but $5 / TB scanned. Overkill for ~2 GB. |
| Custom Lambda + `grafana-json-datasource` | JSON time-series API | Most control. Most code to maintain. |

For a home project the community plugin is the obvious pick. The
queries in `ruuvitag-archive.queries.md` are written for that plugin.

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
