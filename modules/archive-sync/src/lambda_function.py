"""Daily copy of yesterday's live readings into the historical archive.

Runs once a day on an EventBridge schedule, queries the live table
for each known MAC in yesterday's UTC window, and writes the rows to
the historical table keyed on the human-readable sensor name.
Idempotent: re-running a day overwrites the same (name, ts_ms) keys
with the same values.

Backfill: invoke directly with {"date": "YYYY-MM-DD"} to copy a
specific UTC day instead of yesterday.

Configuration (env vars):
  LIVE_TABLE_NAME      partition: mac, sort: ts_ms
  ARCHIVE_TABLE_NAME   partition: name, sort: ts_ms
  NAME_LOOKUP          JSON map of MAC (no colons, uppercase) -> name
"""

import json
import logging
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

log = logging.getLogger()
log.setLevel(logging.INFO)

DDB = boto3.resource("dynamodb")
LIVE_TABLE = os.environ["LIVE_TABLE_NAME"]
ARCHIVE_TABLE = os.environ["ARCHIVE_TABLE_NAME"]
NAME_LOOKUP = json.loads(os.environ["NAME_LOOKUP"])

# Fields to carry over to the historical schema. Anything else (battery,
# rssi, ...) is dropped — those are useful for live troubleshooting,
# not for long-term temperature/humidity charts.
COPY_FIELDS = ("temperature", "humidity", "pressure", "dew_point", "air_density")


def _mac_with_colons(mac_clean: str) -> str:
    return ":".join(mac_clean[i:i + 2] for i in range(0, 12, 2))


def _utc_day_window(day: datetime) -> tuple[int, int]:
    start = day.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc)
    end = start + timedelta(days=1)
    return int(start.timestamp() * 1000), int(end.timestamp() * 1000)


def handler(event, _ctx):
    if event and event.get("date"):
        day = datetime.strptime(event["date"], "%Y-%m-%d")
    else:
        day = datetime.now(timezone.utc) - timedelta(days=1)
    start_ms, end_ms = _utc_day_window(day)

    live = DDB.Table(LIVE_TABLE)
    archive = DDB.Table(ARCHIVE_TABLE)

    total_copied = 0
    per_sensor = {}

    for mac_clean, name in NAME_LOOKUP.items():
        mac = _mac_with_colons(mac_clean)
        n = 0
        last = None
        while True:
            kwargs = {
                "KeyConditionExpression": Key("mac").eq(mac) & Key("ts_ms").between(start_ms, end_ms - 1),
            }
            if last:
                kwargs["ExclusiveStartKey"] = last
            res = live.query(**kwargs)
            items = res.get("Items", [])
            if items:
                with archive.batch_writer() as batch:
                    for item in items:
                        new_item = {"name": name, "ts_ms": item["ts_ms"]}
                        for f in COPY_FIELDS:
                            v = item.get(f)
                            if v is not None:
                                new_item[f] = v
                        batch.put_item(Item=new_item)
                n += len(items)
            last = res.get("LastEvaluatedKey")
            if not last:
                break
        per_sensor[name] = n
        total_copied += n

    log.info("copied %d rows for window %d..%d: %s", total_copied, start_ms, end_ms, per_sensor)
    return {
        "copied": total_copied,
        "per_sensor": per_sensor,
        "from": start_ms,
        "to": end_ms,
    }
