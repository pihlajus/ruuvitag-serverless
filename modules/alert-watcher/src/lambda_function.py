"""Hourly check that every Ruuvitag sensor is still publishing.

Looks up the most recent ts_ms for each known MAC in the live table
and emails an alert via SNS if anything is older than the threshold.
A dead battery, a Pi reboot, or a BLE outage will all surface here.

No deduplication: while a sensor stays silent, an email goes out
every run. If that's noisy, lower the EventBridge schedule frequency
or extend the threshold.
"""

import json
import logging
import os
import time

import boto3
from boto3.dynamodb.conditions import Key

log = logging.getLogger()
log.setLevel(logging.INFO)

LIVE_TABLE = os.environ["LIVE_TABLE_NAME"]
SNS_TOPIC = os.environ["SNS_TOPIC_ARN"]
NAME_LOOKUP = json.loads(os.environ["NAME_LOOKUP"])
THRESHOLD_MIN = int(os.environ.get("THRESHOLD_MINUTES", "60"))

DDB = boto3.resource("dynamodb")
SNS = boto3.client("sns")


def _mac_with_colons(mac_clean: str) -> str:
    return ":".join(mac_clean[i:i + 2] for i in range(0, 12, 2))


def _last_ts(table, mac: str):
    res = table.query(
        KeyConditionExpression=Key("mac").eq(mac),
        ScanIndexForward=False,
        Limit=1,
        ProjectionExpression="ts_ms",
    )
    items = res.get("Items", [])
    return int(items[0]["ts_ms"]) if items else None


def handler(event, _ctx):
    now_ms = int(time.time() * 1000)
    threshold_ms = THRESHOLD_MIN * 60 * 1000
    table = DDB.Table(LIVE_TABLE)

    stale = []
    statuses = {}
    for mac_clean, name in NAME_LOOKUP.items():
        last = _last_ts(table, _mac_with_colons(mac_clean))
        if last is None:
            age = None
            stale_now = True
        else:
            age = now_ms - last
            stale_now = age > threshold_ms
        statuses[name] = {"last_ts_ms": last, "age_minutes": (age // 60000) if age else None}
        if stale_now:
            stale.append({"name": name, "age_minutes": (age // 60000) if age else "n/a"})

    log.info("checked %d sensors, %d stale: %s", len(NAME_LOOKUP), len(stale), statuses)

    if stale:
        lines = "\n".join(
            f"  - {s['name']}: viimeisin lukema {s['age_minutes']} min sitten"
            for s in stale
        )
        body = (
            f"Ruuvitag-sensoreita hiljaa yli {THRESHOLD_MIN} minuuttia:\n\n"
            f"{lines}\n\n"
            "Mahdolliset syyt: patteri loppu, BLE-yhteys katkennut, "
            "Pi-publisher pysähtynyt, tai EC2:n vanha collector ottaa "
            "BLE-radion (jos vielä elossa).\n\n"
            "Sähköposti tulee uudelleen joka tunti niin kauan kuin "
            "sensori on hiljaa."
        )
        SNS.publish(
            TopicArn=SNS_TOPIC,
            Subject=f"Ruuvitag — {len(stale)} sensori{'a' if len(stale) > 1 else ''} pimeänä",
            Message=body,
        )

    return {"checked": len(NAME_LOOKUP), "stale": len(stale), "statuses": statuses}
