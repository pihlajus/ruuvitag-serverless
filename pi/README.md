# Pi side — MQTT publisher

The Raspberry Pi reads BLE advertisements from Ruuvitag sensors and
publishes the latest reading per tag to AWS IoT Core every minute.

## Files

- `ruuvitag_publish.py` — the publisher. All config via env vars.
- `requirements.txt` — Python dependencies.
- `ruuvitag.service.example` — systemd unit template.

## Install

These steps assume Raspbian / Raspberry Pi OS, Python 3.7+ and a
working Bluetooth stack. On older Buster you may need to point apt
at `legacy.raspbian.org` first.

```sh
sudo apt-get install -y python3-venv libglib2.0-dev libbluetooth-dev libssl-dev cmake

# Place the publisher and a venv under /opt
sudo mkdir -p /opt/ruuvitag
sudo cp ruuvitag_publish.py /opt/ruuvitag/

sudo python3 -m venv /opt/ruuvitag-venv
sudo /opt/ruuvitag-venv/bin/pip install --upgrade pip wheel
sudo /opt/ruuvitag-venv/bin/pip install -r requirements.txt
```

> On armv7l + Python 3.7 there is no prebuilt `awscrt` wheel — pip
> compiles it from source, which takes 20-40 minutes on a Pi 3. Be
> patient.

## Certificates

The cert and key are produced by the `iot-ingestion` Terraform module.
From the repository root:

```sh
cd environments/home
terraform output -raw certificate_pem > cert.pem
terraform output -raw private_key > private.key
```

Plus the AWS Root CA:

```sh
curl -o AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

Copy all three to the Pi and lock down permissions:

```sh
sudo install -d -m 700 /etc/ruuvitag
sudo install -m 600 cert.pem private.key AmazonRootCA1.pem /etc/ruuvitag/
```

## Run as a service

```sh
sudo cp ruuvitag.service.example /etc/systemd/system/ruuvitag.service
# Edit IOT_ENDPOINT and IOT_CLIENT_ID to match your stack
sudo systemctl daemon-reload
sudo systemctl enable --now ruuvitag.service
sudo journalctl -u ruuvitag -f
```

## Run manually for testing

```sh
sudo IOT_ENDPOINT=... \
     IOT_CLIENT_ID=ruuvitag-pi-home \
     IOT_CERT_PATH=/etc/ruuvitag/cert.pem \
     IOT_KEY_PATH=/etc/ruuvitag/private.key \
     IOT_CA_PATH=/etc/ruuvitag/AmazonRootCA1.pem \
     /opt/ruuvitag-venv/bin/python /opt/ruuvitag/ruuvitag_publish.py
```

`sudo` is needed because BLE scanning requires `CAP_NET_RAW` /
`CAP_NET_ADMIN`. On a multi-user box you'd grant these to the Python
binary via `setcap` instead.
