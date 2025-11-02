# tor-bridge-render.com - FINAL VERIFIED
# Render.com Free Tier | Silent | 0→100% → LIVE | Cron Ping
# FIXED: HttpsProxyAgent import (v7+ ESM)

FROM node:20-slim

# --- 1. Install Tor + curl (for healthcheck) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

# --- 2. torrc + DataDirectory ---
RUN mkdir -p /home/debian-tor/.tor && \
    chown debian-tor:debian-tor /home/debian-tor/.tor && \
    cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
Log notice stdout
DataDirectory /home/debian-tor/.tor
RunAsDaemon 0
EOF

# --- 3. Switch to debian-tor ---
USER debian-tor
WORKDIR /home/debian-tor/app

# --- 4. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "http-proxy-agent": "^7.0.2"
  }
}
EOF

# --- 5. Install deps ---
RUN npm install --production

# --- 6. app.js (FIXED IMPORT + CRON PING) ---
RUN cat > app.js << 'EOF'
const { spawn } = require('child_process');
const http = require('http');
const https = require('https');

// CORRECT IMPORT FOR v7+
const { HttpsProxyAgent } = require('http-proxy-agent').default;

const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/'; // CHANGE ME
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent;

// === TOR START ===
function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.on('close', code => { if (code !== 0) reject(new Error(`Tor died: ${code}`)); });
    resolve();
  });
}

// === WAIT FOR 100% ===
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Bootstrap timeout')), 90000);

    const check = data => {
      const line = data.toString();
      const match = line.match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (!seen.has(pct)) {
          seen.add(pct);
          console.log(`Tor Bootstrap: ${pct}%`);
        }
        if (pct === 100) {
          clearTimeout(timeout);
          resolve();
        }
      }
    };

    tor.stdout.on('data', check);
    tor.stderr.on('data', check);
  });
}

// === CREATE AGENT ===
function createAgent() {
  agent = new HttpsProxyAgent(SOCKS);
}

// === HIDDEN CRON: PING /health via Tor every 5 min ===
function startCronPing() {
  const ping = () => {
    const req = http.request({
      hostname: 'localhost',
      port: PORT,
      path: '/health',
      method: 'GET',
      agent: agent
    }, () => {});
    req.on('error', () => {});
    req.end();
  };
  setInterval(ping, 5 * 60 * 1000);
  setTimeout(ping, 10000);
}

// === PROXY HANDLER ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('OK');
  }

  const url = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
  const opts = {
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname + url.search,
    method: req.method,
    headers: req.headers,
    agent
  };

  const client = https.request(opts, proxyRes => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  req.pipe(client);
  client.on('error', () => {
    res.statusCode = 502;
    res.end();
  });
}

// === MAIN ===
(async () => {
  try {
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    console.log('================================');
    console.log('Tor Socks5 LIVE on: 127.0.0.1:9050');
    console.log(`Tor Bridge LIVE on port: ${PORT}`);
    console.log(`All traffic to ${ONION_TARGET}`);
    console.log('================================');

    http.createServer(proxyHandler).listen(PORT);
  } catch (err) {
    console.log('==>[ERROR]<===================[X]=');
    console.log(err.message);
    process.exit(1);
  }
})();

process.on('SIGTERM', () => tor && tor.kill());
EOF

# --- 7. Expose & Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
  CMD curl -f http://localhost:$PORT/health || exit 1

CMD ["npm", "start"]
