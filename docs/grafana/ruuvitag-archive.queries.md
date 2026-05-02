# Archive dashboard — DynamoDB queries

Query snippets for the historical table `ruuvitag-readings-historical-home`.
Schema: `name` (HASH, S) + `ts_ms` (RANGE, N). Attributes: `temperature`,
`humidity`, `pressure`, `dew_point`, `air_density` (all N).

The community `grafana-dynamodb-datasource` plugin takes a JSON query
body. The shape below is what each panel needs. Time range comes from
Grafana's selected interval — the plugin substitutes `$__from` and
`$__to` (epoch ms).

## Per-panel queries

### Outdoor temperature graph (Ulko)

```json
{
  "tableName": "ruuvitag-readings-historical-home",
  "keyConditionExpression": "#n = :n AND ts_ms BETWEEN :from AND :to",
  "expressionAttributeNames":  { "#n": "name" },
  "expressionAttributeValues": {
    ":n":    { "S": "Ulko" },
    ":from": { "N": "$__from" },
    ":to":   { "N": "$__to" }
  },
  "projectionExpression": "ts_ms, temperature"
}
```

Same query for `Sisä` and `Sauna` — change `:n`. Same for other
fields — change `projectionExpression`.

### All-time maximum (sauna)

```json
{
  "tableName": "ruuvitag-readings-historical-home",
  "keyConditionExpression": "#n = :n",
  "expressionAttributeNames":  { "#n": "name" },
  "expressionAttributeValues": { ":n": { "S": "Sauna" } },
  "projectionExpression": "ts_ms, temperature"
}
```

Then in panel transformations:
1. `Reduce → Max → temperature`
2. Display as Stat panel

### Daily max graph (sauna)

Same query as the temperature graph, then transformations:
1. `Group by time → 24h → max(temperature)`
2. Display as bar chart

## Why transformations carry so much weight

DynamoDB Query returns rows; it doesn't aggregate. So InfluxQL
operations like `mean(temperature) GROUP BY time(5m)` translate to:

1. **DynamoDB query** that pulls the raw rows for the time window
2. **Grafana transformation** (`Group by time` + reducer) that
   collapses them into the bucket size we want

For the historical table this is fine — it's downsampled to 1-min
means already, so the query window × ~3 sensors is small (a year of
data is ~1.5M rows, returned in pages).

## Item count guard

A wide query like "all-time" pulls everything for one sensor — ~5M
rows for six years × 1-minute downsample. Grafana panels apply a
default 1000-row limit; bump it in the panel options for full-history
views. Nothing blows up cost-wise (DynamoDB Query is read-capacity
based, ~$0.25 per million eventually-consistent reads at 4 KB each;
5M × 200 B is ~250 RCU = $0.0001).
