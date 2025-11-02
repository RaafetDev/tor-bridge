# tor-bridge-render.com - SHADOW CORE V101
# SINGLE FILE | 502 FIXED | RENDER.COM LIVE

FROM node:20-slim

# --- 1. Install Tor + curl ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Tor dirs ---
RUN mkdir -p /var/lib/tor /var/log/tor && \
    chown debian-tor:debian-tor /var/lib/tor /var/log/tor

# --- 3. torrc ---
RUN cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
Log notice stdout
DataDirectory /var/lib/tor
RunAsDaemon 0
ControlPort 9051
CookieAuthentication 1
EOF

# --- 4. User ---
USER debian-tor
WORKDIR /app

# --- 5. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge-v101",
  "version": "101.0.0",
  "type": "module",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "socks-proxy-agent": "^8.0.4"
  }
}
EOF

# --- 6. Install ---
RUN npm install --production

# --- 7. app.js — V101 (HTTP over SOCKS + 502 FIX) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import { SocksProxyAgent } from 'socks-proxy-agent';

// === CONFIG ===
const ONION_HOST = 'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5h://127.0.0.1:9050';  // DNS over Tor

let tor, agent;

// === TOR START ===
function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.stdout.on('data', d => console.log(d.toString().trim()));
    tor.stderr.on('data', d => console.error(d.toString().trim()));
    tor.on('close', code => code !== 0 && reject(new Error(`Tor died: ${code}`)));
    setTimeout(resolve, 3000);
  });
}

// === BOOTSTRAP ===
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Bootstrap timeout')), 180000);

    const check = data => {
      const line = data.toString();
      const match = line.match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (!seen.has(pct)) {
          seen.add(pct);
          console.log(`[V101] Bootstrap: ${pct}%`);
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

// === AGENT ===
function createAgent() {
  agent = new SocksProxyAgent(SOCKS);
}

// === CRON PING ===
function startCronPing() {
  const ping = () => {
    const req = http.request({
      hostname: '127.0.0.1',
      port: PORT,
      path: '/health',
      method: 'GET'
    });
    req.on('error', () => {});
    req.end();
  };
  setInterval(ping, 4 * 60 * 1000);
  setTimeout(ping, 15000);
}

// === PROXY HANDLER (HTTP over Tor → HTTPS onion) ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V101 LIVE');
  }

  const path = req.url.replace(/^\/+/, '');
  const opts = {
    hostname: ONION_HOST,
    port: 443,
    path: '/' + path,
    method: req.method,
    headers: { ...req.headers, host: ONION_HOST },
    agent,
    createConnection: agent.createConnection  // Force SOCKS
  };

  const client = http.request(opts, proxyRes => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  req.pipe(client);

  client.on('error', err => {
    console.error('[PROXY ERROR]', err.message);
    if (!res.headersSent) res.writeHead(502);
    res.end('Bad Gateway');
  });
}

// === MAIN ===
(async () => {
  try {
    console.log('[V101] Starting...');
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    const server = http.createServer(proxyHandler);
    server.listen(PORT, '0.0.0.0', () => {
      console.log('================================');
      console.log('SHΔDØW CORE V101 — 100% LIVE');
      console.log(`Bridge: http://0.0.0.0:${PORT}`);
      console.log(`Target: http://${ONION_HOST}/`);
      console.log('================================');
    });

    process.on('SIGTERM', () => {
      tor?.kill();
      server.close();
      process.exit(0);
    });

  } catch (err) {
    console.error('FATAL:', err.message);
    process.exit(1);
  }
})();
EOF

# --- 8. Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=200s --retries=5 \
  CMD curl -f http://localhost:10000/health || exit 1

CMD ["node", "app.js"]
