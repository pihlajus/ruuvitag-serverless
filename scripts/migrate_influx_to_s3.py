#!/usr/bin/env python3
"""One-shot migration: InfluxDB -> gzipped NDJSON in S3 -> DynamoDB Import.

Run from a host that can reach the legacy InfluxDB and has an aws CLI
with credentials for the target account. Easiest path is an SSH tunnel
from a workstation to the legacy EC2:

    ssh -L 8087:localhost:8086 -N -f ubuntu@<ec2-ip>

then run this script with INFLUX_URL=http://localhost:8087.

Two phases, each iterates month by month so progress is visible:

  1. Downsample `ruuvi_measurements` -> `ruuvi_1m` (1-minute means).
     Idempotent only if ruuvi_1m doesn't already contain rows for the
     month; rerunning over an existing month will duplicate. Drop the
     measurement before retrying:
         DROP MEASUREMENT "ruuvi_1m"

  2. Export `ruuvi_1m` to gzipped NDJSON in DynamoDB Import format,
     uploading one file per month. Sensor names are normalised:
     Terassi -> Ulko, Eteinen -> Sisä; anything else is dropped.

Configuration is via environment variables (no secrets in argv):

  INFLUX_URL    default http://localhost:8086
  INFLUX_DB     default ruuvi
  INFLUX_USER   required
  INFLUX_PW     required
  S3_BUCKET     required for export (the ruuvitag-migration-<account>
                bucket)
  S3_PREFIX     default historical/
  START_MONTH   optional, YYYY-MM (default 2020-03)
  END_MONTH     optional, YYYY-MM (default current month + 1)

Phases (default is both):
  --downsample-only
  --export-only
"""

import base64
import datetime as dt
import gzip
import json
import os
import subprocess
import sys
import time as _time
import urllib.parse
import urllib.request


INFLUX_URL = os.environ.get("INFLUX_URL", "http://localhost:8086")
INFLUX_DB = os.environ.get("INFLUX_DB", "ruuvi")
INFLUX_USER = os.environ["INFLUX_USER"]
INFLUX_PW = os.environ["INFLUX_PW"]
S3_BUCKET = os.environ.get("S3_BUCKET", "")
S3_PREFIX = os.environ.get("S3_PREFIX", "historical/").rstrip("/") + "/"

NAME_RENAME = {"Terassi": "Ulko", "Eteinen": "Sisä", "Sauna": "Sauna"}
KEEP_NAMES = set(NAME_RENAME.values())

_AUTH = base64.b64encode(f"{INFLUX_USER}:{INFLUX_PW}".encode()).decode()


def _query(q, epoch="ms"):
    # InfluxDB accepts POST for both read and write queries.
    body = urllib.parse.urlencode({"db": INFLUX_DB, "q": q, "epoch": epoch}).encode()
    req = urllib.request.Request(
        f"{INFLUX_URL}/query",
        data=body,
        headers={
            "Authorization": f"Basic {_AUTH}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=1800) as r:
        return json.loads(r.read())


def iter_months(start, end):
    cur = start.replace(day=1)
    end_exclusive = end.replace(day=1)
    while cur < end_exclusive:
        nxt = (cur + dt.timedelta(days=32)).replace(day=1)
        yield cur, nxt
        cur = nxt


def downsample_month(start, end):
    q = (
        'SELECT mean("temperature") AS temperature, '
        'mean("humidity") AS humidity, '
        'mean("pressure") AS pressure, '
        'mean("dewPoint") AS dew_point, '
        'mean("airDensity") AS air_density '
        'INTO "ruuvi_1m" '
        'FROM "ruuvi_measurements" '
        f"WHERE time >= '{start.isoformat()}' AND time < '{end.isoformat()}' "
        'GROUP BY time(1m), "name" '
        "fill(none)"
    )
    res = _query(q)
    results = res.get("results", [{}])[0]
    if "error" in results:
        raise RuntimeError(f"downsample {start:%Y-%m} failed: {results['error']}")
    series = results.get("series", [])
    if not series:
        return 0
    written = series[0]["values"][0][1]
    return int(written)


def to_item(row, columns, name):
    item = {"name": {"S": name}}
    for col, val in zip(columns, row):
        if val is None:
            continue
        if col == "time":
            item["ts_ms"] = {"N": str(int(val))}
        elif col == "pressure":
            # Legacy InfluxDB stores Pa; standardise on hPa to match the Pi publisher.
            item[col] = {"N": str(val / 100.0)}
        elif col in ("temperature", "humidity", "dew_point", "air_density"):
            item[col] = {"N": str(val)}
    return {"Item": item} if "ts_ms" in item else None


def export_month(start, end):
    # GROUP BY "name" so InfluxDB returns one series per tag value with
    # the tag in the series' tags dict — much easier to consume than a
    # column-shaped result.
    q = (
        'SELECT "temperature","humidity","pressure","dew_point","air_density" '
        'FROM "ruuvi_1m" '
        f"WHERE time >= '{start.isoformat()}' AND time < '{end.isoformat()}' "
        'GROUP BY "name"'
    )
    res = _query(q)
    series = res.get("results", [{}])[0].get("series", [])
    if not series:
        return 0

    fname = f"/tmp/ruuvi-{start:%Y-%m}.ndjson.gz"
    n = 0
    with gzip.open(fname, "wt", encoding="utf-8") as f:
        for s in series:
            cols = s["columns"]
            tags = s.get("tags") or {}
            legacy_name = tags.get("name")
            if not legacy_name:
                continue
            mapped = NAME_RENAME.get(legacy_name)
            if mapped is None or mapped not in KEEP_NAMES:
                continue
            for row in s["values"]:
                item = to_item(row, cols, mapped)
                if item:
                    f.write(json.dumps(item, ensure_ascii=False) + "\n")
                    n += 1

    if n == 0:
        os.remove(fname)
        return 0

    key = f"{S3_PREFIX}{os.path.basename(fname)}"
    subprocess.check_call(
        ["aws", "s3", "cp", "--only-show-errors", fname, f"s3://{S3_BUCKET}/{key}"]
    )
    os.remove(fname)
    return n


def fmt(t):
    return _time.strftime("%H:%M:%S", _time.localtime(t))


def parse_range():
    today = dt.date.today()
    start = dt.date.fromisoformat(os.environ.get("START_MONTH", "2020-03") + "-01")
    end_month = os.environ.get("END_MONTH", today.strftime("%Y-%m"))
    end = dt.date.fromisoformat(end_month + "-01") + dt.timedelta(days=32)
    end = end.replace(day=1)
    return start, end


def main():
    do_downsample = "--export-only" not in sys.argv
    do_export = "--downsample-only" not in sys.argv
    if do_export and not S3_BUCKET:
        sys.exit("S3_BUCKET required for export phase")

    start, end = parse_range()
    months = list(iter_months(start, end))
    print(f"range: {start:%Y-%m} -> {end:%Y-%m} ({len(months)} months)")

    if do_downsample:
        print(f"\n[1/2] downsample to ruuvi_1m  (started {fmt(_time.time())})")
        t0 = _time.time()
        total = 0
        for i, (s, e) in enumerate(months, 1):
            t = _time.time()
            n = downsample_month(s, e)
            total += n
            elapsed = _time.time() - t
            print(
                f"  [{i:>3}/{len(months)}] {s:%Y-%m}: {n:>7d} rows  ({elapsed:5.1f}s)",
                flush=True,
            )
        print(f"      total {total} rows in {(_time.time()-t0)/60:.1f} min")

    if do_export:
        print(f"\n[2/2] export to s3://{S3_BUCKET}/{S3_PREFIX}  (started {fmt(_time.time())})")
        t0 = _time.time()
        total = 0
        for i, (s, e) in enumerate(months, 1):
            t = _time.time()
            n = export_month(s, e)
            total += n
            elapsed = _time.time() - t
            print(
                f"  [{i:>3}/{len(months)}] {s:%Y-%m}: {n:>7d} rows  ({elapsed:5.1f}s)",
                flush=True,
            )
        print(f"      total {total} rows in {(_time.time()-t0)/60:.1f} min")


if __name__ == "__main__":
    main()
