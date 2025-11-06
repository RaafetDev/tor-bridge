FROM debian:bookworm-slim

# Install Tor, tinyproxy, curl, cron, and wget
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    cron \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Download Playit agent
RUN wget -O /usr/local/bin/playit https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 && \
    chmod +x /usr/local/bin/playit

# Create Tor configuration
RUN mkdir -p /app/tor-data && chmod 700 /app/tor-data
RUN cat > /app/tor-data/torrc <<'EOF'
DataDirectory /app/tor-data
SocksPort 0.0.0.0:9050
Log notice stdout
EOF

# Create Tinyproxy configuration
RUN mkdir -p /app/logs
RUN cat > /app/tinyproxy.conf <<'EOF'
Port 8888
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
LogFile "/app/logs/tinyproxy.log"
LogLevel Info
MaxClients 100
Allow 0.0.0.0/0
ViaProxyName "TorProxy"
DisableViaHeader No
Upstream socks5 127.0.0.1:9050
EOF

# Create keepalive script that makes external requests through Tor
RUN cat > /app/keepalive.sh <<'EOF'
#!/bin/bash

# Array of real websites to visit (simulating real browser behavior)
URLS=(
    "http://example.com"
    "http://httpbin.org/ip"
    "http://icanhazip.com"
    "http://ifconfig.me"
    "http://api.ipify.org"
    "http://checkip.amazonaws.com"
)

# Array of User-Agents (real browsers)
USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
)

# Pick random URL and User-Agent
RANDOM_URL=${URLS[$RANDOM % ${#URLS[@]}]}
RANDOM_UA=${USER_AGENTS[$RANDOM % ${#USER_AGENTS[@]}]}

# Generate random request ID
REQUEST_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)

# Log the attempt
echo "[$(date -Iseconds)] Keepalive: Visiting $RANDOM_URL through Tor proxy"

# Make request through HTTP proxy (which uses Tor)
# This simulates a real external browser request coming from OUTSIDE
curl -s -x http://127.0.0.1:8888 \
     -A "$RANDOM_UA" \
     -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
     -H "Accept-Language: en-US,en;q=0.9" \
     -H "Accept-Encoding: gzip, deflate" \
     -H "DNT: 1" \
     -H "Connection: keep-alive" \
     -H "Upgrade-Insecure-Requests: 1" \
     -H "Cache-Control: max-age=0" \
     -H "X-Request-ID: keepalive-$REQUEST_ID" \
     --max-time 30 \
     "$RANDOM_URL" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date -Iseconds)] Keepalive: Success! (appears as external Tor traffic)"
else
    echo "[$(date -Iseconds)] Keepalive: Failed"
fi
EOF

RUN chmod +x /app/keepalive.sh

# Setup cron job (every 5 minutes)
RUN echo "*/5 * * * * /app/keepalive.sh >> /app/logs/keepalive.log 2>&1" | crontab -

# Create startup script
RUN cat > /app/start.sh <<'EOF'
#!/bin/bash

echo "========================================"
echo "   Free Worldwide Tor HTTP Proxy"
echo "========================================"
echo ""

# Start Tor
echo "[$(date -Iseconds)] Starting Tor..."
tor -f /app/tor-data/torrc &
TOR_PID=$!

# Wait for Tor to bootstrap
echo "[$(date -Iseconds)] Waiting for Tor to bootstrap (this may take 1-2 minutes)..."
BOOTSTRAP_ATTEMPTS=0
MAX_ATTEMPTS=60

while [ $BOOTSTRAP_ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if curl -s --socks5 127.0.0.1:9050 http://check.torproject.org 2>&1 | grep -q "Congratulations"; then
        echo "[$(date -Iseconds)] ✓ Tor is fully bootstrapped and working!"
        break
    fi
    BOOTSTRAP_ATTEMPTS=$((BOOTSTRAP_ATTEMPTS + 1))
    sleep 3
done

if [ $BOOTSTRAP_ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    echo "[$(date -Iseconds)] ✗ Tor bootstrap timeout!"
    exit 1
fi

# Start tinyproxy
echo "[$(date -Iseconds)] Starting Tinyproxy..."
tinyproxy -d -c /app/tinyproxy.conf &
TINYPROXY_PID=$!

sleep 3
echo "[$(date -Iseconds)] ✓ Tinyproxy is running on port 8888!"

# Start Playit agent if SECRET_KEY is provided
if [ ! -z "$PLAYIT_SECRET" ]; then
    echo "[$(date -Iseconds)] Starting Playit.gg agent..."
    SECRET_KEY=$PLAYIT_SECRET playit &
    PLAYIT_PID=$!
    sleep 5
    echo "[$(date -Iseconds)] ✓ Playit agent started! Check logs above for tunnel URL"
else
    echo "[$(date -Iseconds)] ℹ No PLAYIT_SECRET provided - proxy only accessible internally"
    echo "[$(date -Iseconds)] ℹ Add PLAYIT_SECRET environment variable for public access"
fi

# Start cron for keepalive
echo "[$(date -Iseconds)] Starting keepalive cron (every 5 minutes)..."
cron

# Run initial keepalive immediately
echo "[$(date -Iseconds)] Running initial keepalive..."
/app/keepalive.sh

echo ""
echo "========================================"
echo "   All services started successfully!"
echo "========================================"
echo ""
echo "HTTP Proxy: 0.0.0.0:8888"
echo "Credentials: free / free"
echo "Backend: Tor SOCKS5 (127.0.0.1:9050)"
echo ""
echo "Test locally:"
echo "  curl -x http://free:free@127.0.0.1:8888 http://check.torproject.org"
echo ""
echo "Keepalive: Active (requests real websites every 5 min)"
echo ""

# Keep container running and monitor processes
while kill -0 $TOR_PID 2>/dev/null && kill -0 $TINYPROXY_PID 2>/dev/null; do
    sleep 60
done

echo "[$(date -Iseconds)] ✗ Critical process died, shutting down..."
EOF

RUN chmod +x /app/start.sh

# Expose tinyproxy port (Render will auto-detect this)
EXPOSE 8888

# Start everything
CMD ["/app/start.sh"]
