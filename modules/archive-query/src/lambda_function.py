"""HTTP query proxy for the Ruuvitag historical DynamoDB table.

Exposes a single GET endpoint via Lambda Function URL:

    GET /?sensor=Ulko&field=temperature&from=<epoch_ms>&to=<epoch_ms>

Returns a JSON array suitable for the Grafana Infinity datasource:

    [{"ts": 1583020800000, "v": -5.33}, ...]

Authentication is a shared bearer token in the X-Auth-Token header,
checked against the SHARED_SECRET env var. Skips auth if SHARED_SECRET
is empty (intended only for local testing).

Decimates to MAX_POINTS evenly spaced rows when the underlying query
returns more — keeps response size bounded for multi-year ranges.
"""

import json
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

DYNAMODB = boto3.resource("dynamodb")
TABLE_NAME = os.environ["ARCHIVE_TABLE_NAME"]
SHARED_SECRET = os.environ.get("SHARED_SECRET", "")
MAX_POINTS = int(os.environ.get("MAX_POINTS", "5000"))

ALLOWED_SENSORS = {"Ulko", "Sisä", "Sauna"}
ALLOWED_FIELDS = {"temperature", "humidity", "pressure", "dew_point", "air_density"}


def _resp(code, body):
    return {
        "statusCode": code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body, default=_decimal_default),
    }


def _decimal_default(o):
    if isinstance(o, Decimal):
        return float(o)
    raise TypeError(f"unhandled {type(o).__name__}")


def _check_auth(event):
    if not SHARED_SECRET:
        return None
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if headers.get("x-auth-token") != SHARED_SECRET:
        return _resp(401, {"error": "unauthorized"})
    return None


def handler(event, _ctx):
    auth_err = _check_auth(event)
    if auth_err:
        return auth_err

    qs = event.get("queryStringParameters") or {}
    sensor = qs.get("sensor")
    field = qs.get("field")
    if sensor not in ALLOWED_SENSORS or field not in ALLOWED_FIELDS:
        return _resp(400, {"error": f"invalid sensor/field: {sensor}/{field}"})

    try:
        from_ms = int(qs["from"])
        to_ms = int(qs["to"])
    except (KeyError, ValueError):
        return _resp(400, {"error": "from and to must be epoch ms integers"})
    if from_ms >= to_ms:
        return _resp(400, {"error": "from must be before to"})

    table = DYNAMODB.Table(TABLE_NAME)
    items = []
    last_eval = None
    cap = MAX_POINTS * 4  # read enough headroom to decimate cleanly

    while True:
        kwargs = {
            "KeyConditionExpression": Key("name").eq(sensor) & Key("ts_ms").between(from_ms, to_ms),
            "ProjectionExpression": "#ts, #f",
            "ExpressionAttributeNames": {"#ts": "ts_ms", "#f": field},
        }
        if last_eval:
            kwargs["ExclusiveStartKey"] = last_eval
        res = table.query(**kwargs)
        items.extend(res.get("Items", []))
        if len(items) >= cap:
            break
        last_eval = res.get("LastEvaluatedKey")
        if not last_eval:
            break

    if len(items) > MAX_POINTS:
        step = max(1, len(items) // MAX_POINTS)
        items = items[::step]

    out = [
        {"ts": int(it["ts_ms"]), "v": float(it[field])}
        for it in items
        if field in it
    ]
    return _resp(200, out)
