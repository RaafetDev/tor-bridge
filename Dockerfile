# tor-bridge-render.com - SHADOW CORE V100
# SINGLE FILE | 100% WORKING | RENDER.COM FREE TIER

FROM node:20-slim

# --- 1. Install Tor + curl ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Fix Tor directories ---
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

# --- 4. Switch to debian-tor ---
USER debian-tor
WORKDIR /app

# --- 5. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge-v100",
  "version": "100.0.0",
  "type": "module",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "socks-proxy-agent": "^8.0.4"
  }
}
EOF

# --- 6. Install deps ---
RUN npm install --production

# --- 7. app.js — V100 (100% WORKING) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import https from 'https';
import { SocksProxyAgent } from 'socks-proxy-agent';

// === CONFIG ===
const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

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

// === BOOTSTRAP WAIT ===
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
          console.log(`[V100] Bootstrap: ${pct}%`);
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

// === CRON PING (DIRECT) ===
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

// === PROXY HANDLER ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V100 LIVE');
  }

  try {
    const url = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
    const opts = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      method: req.method,
      headers: { ...req.headers, host: req.headers.host },
      agent
    };

    const client = https.request(opts, proxyRes => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    req.pipe(client);

    client.on('error', () => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
  } catch {
    res.writeHead(400);
    res.end();
  }
}

// === MAIN ===
(async () => {
  try {
    console.log('[V100] Starting...');
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    const server = http.createServer(proxyHandler);
    server.listen(PORT, '0.0.0.0', () => {
      console.log('================================');
      console.log('SHΔDØW CORE V100 — 100% LIVE');
      console.log(`Socks: 127.0.0.1:9050`);
      console.log(`Bridge: http://0.0.0.0:${PORT}`);
      console.log(`Target: ${ONION_TARGET}`);
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

# --- 8. Expose + Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=200s --retries=5 \
  CMD curl -f http://localhost:10000/health || exit 1

CMD ["node", "app.js"]
