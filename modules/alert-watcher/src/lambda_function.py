"""Hourly check that every Ruuvitag sensor is still publishing.

Looks up the most recent ts_ms for each known MAC in the live table.
Anything older than THRESHOLD_MINUTES is considered silent. Per-sensor
cooldown (COOLDOWN_HOURS) prevents the email from spamming when a
sensor stays silent for days — once a sensor has been alerted, the
next email about that same sensor is held back until the cooldown has
elapsed. When a sensor recovers, its cooldown state is cleared, so a
later outage triggers immediately.

State is one SSM parameter holding a JSON map: sensor name → unix-ms
of the last alert. Standard parameters are free.
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
COOLDOWN_HOURS = int(os.environ.get("COOLDOWN_HOURS", "24"))
ALERT_STATE_PARAM = os.environ["ALERT_STATE_PARAM"]

DDB = boto3.resource("dynamodb")
SNS = boto3.client("sns")
SSM = boto3.client("ssm")


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


def _read_state() -> dict:
    try:
        resp = SSM.get_parameter(Name=ALERT_STATE_PARAM)
        return json.loads(resp["Parameter"]["Value"])
    except SSM.exceptions.ParameterNotFound:
        return {}


def _write_state(state: dict) -> None:
    SSM.put_parameter(
        Name=ALERT_STATE_PARAM,
        Value=json.dumps(state),
        Type="String",
        Overwrite=True,
    )


def handler(event, _ctx):
    now_ms = int(time.time() * 1000)
    threshold_ms = THRESHOLD_MIN * 60 * 1000
    cooldown_ms = COOLDOWN_HOURS * 3600 * 1000
    table = DDB.Table(LIVE_TABLE)
    state = _read_state()
    state_dirty = False

    to_alert = []
    statuses = {}
    for mac_clean, name in NAME_LOOKUP.items():
        last = _last_ts(table, _mac_with_colons(mac_clean))
        age_ms = (now_ms - last) if last is not None else None
        is_stale = last is None or age_ms > threshold_ms
        statuses[name] = {
            "last_ts_ms": last,
            "age_minutes": (age_ms // 60000) if age_ms is not None else None,
        }

        if not is_stale:
            if state.pop(name, None) is not None:
                state_dirty = True
            continue

        last_alert = state.get(name)
        if last_alert is None or now_ms - last_alert >= cooldown_ms:
            to_alert.append({
                "name": name,
                "age_minutes": (age_ms // 60000) if age_ms is not None else "n/a",
            })
            state[name] = now_ms
            state_dirty = True

    log.info(
        "checked %d sensors, alerting %d, statuses=%s",
        len(NAME_LOOKUP), len(to_alert), statuses,
    )

    if to_alert:
        lines = "\n".join(
            f"  - {s['name']}: viimeisin lukema {s['age_minutes']} min sitten"
            for s in to_alert
        )
        body = (
            f"Ruuvitag-sensoreita hiljaa yli {THRESHOLD_MIN} minuuttia:\n\n"
            f"{lines}\n\n"
            "Mahdolliset syyt: patteri loppu, BLE-yhteys katkennut tai "
            "Pi-publisher pysähtynyt.\n\n"
            f"Sama sensori muistutetaan korkeintaan {COOLDOWN_HOURS}h "
            "välein. Kun sensori palaa, lasku nollataan ja seuraava katko "
            "hälyttää heti."
        )
        SNS.publish(
            TopicArn=SNS_TOPIC,
            Subject=f"Ruuvitag — {len(to_alert)} sensori{'a' if len(to_alert) > 1 else ''} pimeänä",
            Message=body,
        )

    if state_dirty:
        _write_state(state)

    return {"checked": len(NAME_LOOKUP), "alerted": len(to_alert), "statuses": statuses}
