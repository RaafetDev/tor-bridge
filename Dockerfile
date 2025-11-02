# tor-bridge-render.com - SHADOW CORE V103
# SINGLE FILE | BAD GATEWAY FIXED | FULL HTTPS ONION

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
  "name": "tor-bridge-v103",
  "version": "103.0.0",
  "type": "module",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "node-fetch": "^3.3.2",
    "socks-proxy-agent": "^8.0.4"
  }
}
EOF

# --- 6. Install ---
RUN npm install --production

# --- 7. app.js — V103 (FETCH + SOCKS AGENT) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import fetch from 'node-fetch';
import { SocksProxyAgent } from 'socks-proxy-agent';

// === CONFIG ===
const ONION_URL = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5h://127.0.0.1:9050';

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
          console.log(`[V103] Bootstrap: ${pct}%`);
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

// === PROXY HANDLER (FETCH + STREAM) ===
async function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V103 LIVE');
  }

  const path = req.url === '/' ? '' : req.url;
  const targetUrl = `${ONION_URL}${path}`;

  try {
    const response = await fetch(targetUrl, {
      method: req.method,
      headers: {
        ...req.headers,
        host: new URL(ONION_URL).host
      },
      body: req.method !== 'GET' && req.method !== 'HEAD' ? req : undefined,
      agent,
      redirect: 'manual',
      signal: AbortSignal.timeout(30000)
    });

    const headers = {};
    for (const [key, value] of response.headers.entries()) {
      if (key !== 'transfer-encoding') headers[key] = value;
    }

    res.writeHead(response.status, headers);
    response.body.pipe(res);

  } catch (err) {
    console.error('[FETCH ERROR]', err.message);
    if (!res.headersSent) res.writeHead(502);
    res.end('Bad Gateway');
  }
}

// === MAIN ===
(async () => {
  try {
    console.log('[V103] Starting...');
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    const server = http.createServer((req, res) => {
      req.on('error', () => res.end());
      res.on('error', () => {});
      proxyHandler(req, res).catch(() => {});
    });

    server.listen(PORT, '0.0.0.0', () => {
      console.log('================================');
      console.log('SHΔDØW CORE V103 — 100% LIVE');
      console.log(`Bridge: http://0.0.0.0:${PORT}`);
      console.log(`Target: ${ONION_URL}`);
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
