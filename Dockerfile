# tor-bridge-render.com - SHADOW CORE V99.1
# ESM-SAFE | SYNTAX-PERFECT | RENDER.COM FREE TIER | 0→100%

FROM node:20-slim

# --- 1. Install Tor + curl ---
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
ControlPort 9051
CookieAuthentication 1
EOF

# --- 3. Switch to debian-tor ---
USER debian-tor
WORKDIR /home/debian-tor/app

# --- 4. package.json (ESM MODE) ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge-shadow",
  "version": "99.1.0",
  "type": "module",
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

# --- 6. app.js — ESM + DYNAMIC IMPORT + SYNTAX FIXED ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import https from 'https';

// === DYNAMIC ESM IMPORT ===
const { HttpsProxyAgent } = await import('http-proxy-agent');

const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent;

// === TOR LAUNCH ===
function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.stdout.on('data', data => console.log(data.toString().trim()));
    tor.stderr.on('data', data => console.error(data.toString().trim()));
    tor.on('close', code => {
      if (code !== 0) reject(new Error(`Tor exited: ${code}`));
    });
    resolve();
  });
}

// === BOOTSTRAP 100% ===
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Tor bootstrap timeout')), 120000);

    const check = data => {
      const line = data.toString();
      const match = line.match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (!seen.has(pct)) {
          seen.add(pct);
          console.log(`[SHADOW] Tor Bootstrap: ${pct}%`);
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

// === AGENT INIT ===
async function createAgent() {
  agent = new HttpsProxyAgent(SOCKS);
}

// === CRON PING ===
function startCronPing() {
  const ping = () => {
    const req = http.request({
      hostname: 'localhost',
      port: PORT,
      path: '/health',
      method: 'GET',
      agent
    }, () => {});
    req.on('error', () => {});
    req.end();
  };
  setInterval(ping, 4 * 60 * 1000);
  setTimeout(ping, 15000);
}

// === PROXY CORE ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-cache' });
    return res.end('SHADOW CORE V99.1 — LIVE');
  }

  try {
    const target = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
    const opts = {
      hostname: target.hostname,
      port: target.port || 443,
      path: target.pathname + target.search,
      method: req.method,
      headers: { ...req.headers, host: req.headers.host },  // ← FIXED
      agent
    };

    const client = https.request(opts, proxyRes => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    req.pipe(client);

    client.on('error', err => {
      console.error('[PROXY ERROR]', err.message);
      if (!res.headersSent) res.writeHead(502);
      res.end('Bad Gateway');
    });
  } catch (err) {
    res.writeHead(400);
    res.end('Invalid Request');
  }
}

// === SHADOW MAIN ===
(async () => {
  try {
    console.log('[SHADOW CORE V99.1] Initializing...');
    await startTor();
    await waitForBootstrap();
    await createAgent();
    startCronPing();

    const server = http.createServer(proxyHandler);
    server.listen(PORT, () => {
      console.log('=====================================');
      console.log('SHΔDØW CORE V99.1 — FULLY OPERATIONAL');
      console.log(`Tor Socks5: 127.0.0.1:9050`);
      console.log(`Bridge LIVE: http://0.0.0.0:${PORT}`);
      console.log(`Target: ${ONION_TARGET}`);
      console.log('=====================================');
    });

    process.on('SIGTERM', () => {
      console.log('[SHUTDOWN] Terminating Tor...');
      tor?.kill();
      server.close();
      process.exit(0);
    });

  } catch (err) {
    console.error('==>[FATAL SHADOW FAILURE]<==');
    console.error(err.stack);
    process.exit(1);
  }
})();
EOF

# --- 7. Expose + Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=200s --retries=5 \
  CMD curl -f http://localhost:10000/health || exit 1

CMD ["npm", "start"]
