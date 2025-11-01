# SHΔDØW CORE: ULTRA-LIGHT TOR2WEB PROXY — RENDER.COM FREE TIER
# DEPLOY: Paste into Render > Web Service > Docker > Add Env: ONION_DOMAIN=youronion.onion
# NO COMPILE. NO BLOAT. PURE SHADOW.

FROM ubuntu:22.04

# === ENVIRONMENT: LOCKED & LOADED ===
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# === INSTALL TOR + PYTHON + ESSENTIALS (APT = TRUTH) ===
RUN apt-get update && apt-get install -y --no-install-recommends \
    tor \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# === PYTHON VENV + PROXY DEPENDENCIES ===
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
    gunicorn \
    flask \
    requests[socks] \
    stem

# === TOR CONFIG: SOCKS + CONTROL + ONION RESOLUTION ===
RUN mkdir -p /var/run/tor /var/log/tor
RUN echo "SocksPort 9050" > /etc/tor/torrc \
    && echo "ControlPort 9051" >> /etc/tor/torrc \
    && echo "CookieAuthentication 1" >> /etc/tor/torrc \
    && echo "AutomapHostsOnResolve 1" >> /etc/tor/torrc \
    && echo "Log notice stdout" >> /etc/tor/torrc

# === SHΔDØW TOR2WEB MICRO-ENGINE (PURE PYTHON, NO DISK) ===
WORKDIR /app
RUN cat > app.py << 'PYEOF'
import os
import requests
from flask import Flask, request, Response
import threading
import time
import logging

ONION = os.environ['ONION_DOMAIN']
TOR_SOCKS = "socks5://127.0.0.1:9050"
TIMEOUT = 30
logging.basicConfig(level=logging.INFO)

app = Flask(__name__)

def wait_for_tor():
    for _ in range(60):
        try:
            with open('/var/run/tor/control.authcookie', 'rb') as f:
                cookie = f.read()
            if len(cookie) == 32:
                logging.info("SHΔDØW: Tor control cookie ready.")
                return
        except:
            time.sleep(3)
    raise Exception("SHΔDØW: Tor failed to start.")

threading.Thread(target=wait_for_tor, daemon=True).start()

def proxy_request(path):
    url = f"http://{ONION}{path}"
    proxies = {"http": TOR_SOCKS, "https": TOR_SOCKS}
    headers = {k: v for k, v in request.headers if k.lower() != 'host'}
    
    try:
        resp = requests.request(
            method=request.method,
            url=url,
            headers=headers,
            data=request.get_data(),
            cookies=request.cookies,
            allow_redirects=False,
            stream=True,
            proxies=proxies,
            timeout=TIMEOUT,
            verify=False
        )
        headers_out = [(k, v) for k, v in resp.raw.headers.items()]
        return Response(resp.content, resp.status_code, headers_out, direct_passthrough=True)
    except Exception as e:
        logging.error(f"SHΔDØW ERROR: {e}")
        return "SHΔDØW: Onion unreachable.", 502

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    return proxy_request('/' + path)

@app.route('/.shadow')
def shadow():
    return "SHΔDØW CORE ACTIVE", 200

if __name__ == '__main__':
    app.run()
PYEOF

# === EXPOSE RENDER PORT ===
EXPOSE 10000
ENV PORT=10000

# === FINAL RITUAL: START TOR + GUNICORN ===
CMD /bin/bash -c "\
    tor -f /etc/tor/torrc & \
    sleep 12 && \
    echo 'SHΔDØW: Tor daemon summoned.' && \
    gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 2 --timeout 120 app:app --preload
"
