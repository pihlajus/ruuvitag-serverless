"""Forward Ruuvitag MQTT readings to Grafana Cloud as metrics.

Triggered by an IoT Topic Rule. The rule passes the parsed MQTT
payload as the event dict.

Push uses Grafana Cloud's InfluxDB line-protocol endpoint rather than
Prometheus remote_write. Both end up as the same Mimir-stored metrics
queryable with PromQL — line protocol just avoids needing protobuf +
snappy in the deployment package, which keeps the function pure
stdlib Python.

Resulting metrics (per field): ruuvi_temperature, ruuvi_humidity,
ruuvi_pressure, ruuvi_dew_point, ruuvi_air_density, ruuvi_battery,
ruuvi_rssi. Labels: name, mac.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import urllib.error
import urllib.request

log = logging.getLogger()
log.setLevel(logging.INFO)

NAME_LOOKUP = json.loads(os.environ["NAME_LOOKUP"])  # {"F2FD824D5C5C": "Ulko", ...}
GRAFANA_URL = os.environ["GRAFANA_URL"]
_AUTH = base64.b64encode(
    f"{os.environ['GRAFANA_USERNAME']}:{os.environ['GRAFANA_API_KEY']}".encode()
).decode()

_FIELDS = (
    "temperature",
    "humidity",
    "pressure",
    "dew_point",
    "air_density",
    "battery",
    "rssi",
)


def _line(event: dict, name: str, mac_clean: str) -> str | None:
    fields = []
    for k in _FIELDS:
        v = event.get(k)
        if v is None:
            continue
        fields.append(f"{k}={float(v)}")
    if not fields:
        return None
    ts_ns = int(event["ts_ms"]) * 1_000_000
    return f"ruuvi,name={name},mac={mac_clean} {','.join(fields)} {ts_ns}"


def handler(event, _context):
    mac_clean = str(event.get("mac", "")).replace(":", "").upper()
    name = NAME_LOOKUP.get(mac_clean)
    if not name:
        log.warning("unknown mac=%s — skipping", mac_clean)
        return {"skipped": True, "reason": "unknown mac"}

    line = _line(event, name, mac_clean)
    if not line:
        log.warning("no numeric fields for mac=%s", mac_clean)
        return {"skipped": True, "reason": "no fields"}

    req = urllib.request.Request(
        GRAFANA_URL,
        data=line.encode("utf-8"),
        headers={
            "Authorization": f"Basic {_AUTH}",
            "Content-Type": "text/plain; charset=utf-8",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status not in (200, 204):
                body = resp.read().decode("utf-8", "replace")
                raise RuntimeError(f"push failed: {resp.status} {body}")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        log.error("HTTP %s from grafana: %s", exc.code, body)
        raise

    log.info("pushed name=%s mac=%s", name, mac_clean)
    return {"ok": True, "name": name}
