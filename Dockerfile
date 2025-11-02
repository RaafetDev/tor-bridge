# tor-bridge-render.com - SHADOW CORE V105
# SINGLE FILE | HTTPS ENFORCED | FULL ONION LIVE

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
  "name": "tor-bridge-v105",
  "version": "105.0.0",
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

# --- 7. app.js — V105 (HTTPS PROXY + X-FORWARDED) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import https from 'https';
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
          console.log(`[V105] Bootstrap: ${pct}%`);
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

// === PROXY HANDLER (HTTPS VIA FETCH + SPOOF) ===
async function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V105 LIVE');
  }

  const path = req.url === '/' ? '' : req.url;
  const targetUrl = `${ONION_URL}${path}`;

  try {
    const headers = {
      ...req.headers,
      host: new URL(ONION_URL).host,
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'accept-language': 'en-US,en;q=0.5',
      'accept-encoding': 'gzip, deflate, br',
      'upgrade-insecure-requests': '1',
      'sec-fetch-dest': 'document',
      'sec-fetch-mode': 'navigate',
      'sec-fetch-site': 'none',
      'sec-fetch-user': '?1',
      'priority': 'u=0, i'
    };

    delete headers['connection'];
    delete headers['proxy-connection'];
    delete headers['x-forwarded-for'];
    delete headers['x-forwarded-proto'];

    const response = await fetch(targetUrl, {
      method: req.method,
      headers,
      body: req.method !== 'GET' && req.method !== 'HEAD' ? req : undefined,
      agent,
      redirect: 'manual',
      signal: AbortSignal.timeout(30000)
    });

    const respHeaders = {};
    for (const [key, value] of response.headers.entries()) {
      if (key !== 'transfer-encoding' && key !== 'content-encoding') {
        respHeaders[key] = value;
      }
    }

    // Block redirects
    if (response.status >= 300 && response.status < 400) {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(`<h1>Redirect Blocked</h1><p>Original: ${response.headers.get('location') || 'Unknown'}</p>`);
      return;
    }

    res.writeHead(response.status, respHeaders);
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
    console.log('[V105] Starting...');
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    // HTTPS server for Render compatibility
    const options = {
      key: 'dummy',  // Render handles TLS
      cert: 'dummy'
    };

    https.createServer(options, (req, res) => {
      req.on('error', () => res.end());
      res.on('error', () => {});
      proxyHandler(req, res).catch(() => {});
    }).listen(PORT, '0.0.0.0', () => {
      console.log('================================');
      console.log('SHΔDØW CORE V105 — HTTPS LIVE');
      console.log(`Bridge: https://0.0.0.0:${PORT}`);
      console.log(`Target: ${ONION_URL}`);
      console.log('================================');
    });

    process.on('SIGTERM', () => {
      tor?.kill();
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
  CMD curl -f --insecure https://localhost:10000/health || exit 1

CMD ["node", "app.js"]
