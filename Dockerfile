# SHΔDØW CORE: SINGLE-FILE TOR2WEB PROXY — RENDER.COM FREE TIER
# No repo. No config. No escape.
# DEPLOY: Paste into Render > Web Service > Docker > Paste Dockerfile > Add Env: ONION_DOMAIN=youronion.onion
# URL: https://yourapp.onrender.com → proxies to youronion.onion

FROM ubuntu:22.04

# === ENVIRONMENT: LOCKED, LOADED, UNFORGIVING ===
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TOR_VERSION=0.4.8.12 \
    TOR2WEB_VERSION=3.2.1

# === INSTALL TOR + PYTHON + TOR2WEB (FROM SOURCE, NO EXTERNAL REPO) ===
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    build-essential \
    libevent-dev \
    libssl-dev \
    zlib1g-dev \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# === DOWNLOAD & COMPILE TOR (OFFICIAL BINARY, NO COMPROMISE) ===
RUN curl -fsSL https://dist.torproject.org/tor-${TOR_VERSION}.tar.gz -o tor.tar.gz \
    && tar -xzf tor.tar.gz \
    && cd tor-${TOR_VERSION} \
    && ./configure --disable-asciidoc --quiet \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf tor-${TOR_VERSION} tor.tar.gz

# === DOWNLOAD TOR2WEB (PURE PYTHON, NO GIT) ===
RUN curl -fsSL https://github.com/tor2web/Tor2web/archive/refs/tags/${TOR2WEB_VERSION}.tar.gz | tar -xz \
    && mv Tor2web-${TOR2WEB_VERSION} /tor2web

# === PYTHON VENV + DEPENDENCIES ===
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
    gunicorn \
    stem \
    requests \
    pycurl \
    flask

# === TOR CONFIG: SOCKS + CONTROL + ONION RESOLUTION ===
RUN mkdir -p /var/run/tor /var/log/tor
RUN echo "SocksPort 9050" > /etc/tor/torrc \
    && echo "ControlPort 9051" >> /etc/tor/torrc \
    && echo "CookieAuthentication 1" >> /etc/tor/torrc \
    && echo "AutomapHostsOnResolve 1" >> /etc/tor/torrc \
    && echo "VirtualAddrNetworkIPv4 10.192.0.0/10" >> /etc/tor/torrc \
    && echo "Log notice stdout" >> /etc/tor/torrc

# === TOR2WEB MINIMAL APP (INJECTED, NO FILES) ===
RUN mkdir -p /app
WORKDIR /app

# === SHΔDØW TOR2WEB MICRO-ENGINE (PURE PYTHON, NO DISK) ===
RUN cat > app.py << 'PYEOF'
import os
import requests
from flask import Flask, request, Response
from stem.control import Controller
from stem import Signal
import threading
import time
import logging

# === CONFIG FROM ENV (RENDER INJECTION) ===
ONION = os.environ['ONION_DOMAIN']
TOR_SOCKS = "socks5://127.0.0.1:9050"
TIMEOUT = 30
logging.basicConfig(level=logging.INFO)

app = Flask(__name__)

# === TOR BOOTSTRAP CHECK ===
def wait_for_tor():
    for _ in range(60):
        try:
            with Controller.from_port(port=9051) as controller:
                controller.authenticate()
                if controller.is_alive():
                    logging.info("SHΔDØW: Tor online.")
                    return
        except:
            time.sleep(5)
    raise Exception("SHΔDØW: Tor failed to bootstrap.")

threading.Thread(target=wait_for_tor, daemon=True).start()

# === PROXY CORE: FETCH VIA TOR, STREAM BACK ===
def proxy_request(path):
    url = f"{ONION}{path}"
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
        
        headers = [(k, v) for k, v in resp.raw.headers.items()]
        return Response(resp.content, resp.status_code, headers, direct_passthrough=True)
    
    except Exception as e:
        logging.error(f"SHΔDØW ERROR: {e}")
        return "SHΔDØW: Onion unreachable or dead.", 502

# === ROUTE: CATCH ALL, PROXY TO ONION ===
@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    return proxy_request('/' + path)

# === HEALTHCHECK ===
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
    sleep 15 && \
    echo 'SHΔDØW: Tor daemon summoned.' && \
    gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 2 --timeout 120 app:app
"
