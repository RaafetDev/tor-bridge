# tor-bridge-render.com - FINAL VERIFIED v8
# Render.com Free Tier | Silent | 0→100% → LIVE | EXTERNAL CRON PING via Tor
# EXPRESS + http-proxy-middleware | socks-proxy-agent | SOCKS5H (ONION DNS) | CLEAN URL

FROM node:20-slim

# --- 1. Install Tor + curl ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Create .tor dir & switch user ---
RUN mkdir -p /home/debian-tor/.tor && \
    chown debian-tor:debian-tor /home/debian-tor/.tor

USER debian-tor
WORKDIR /home/debian-tor/app

# --- 3. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge-express",
  "version": "1.0.0",
  "main": "app.js",
  "type": "commonjs",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.21.1",
    "http-proxy-middleware": "^3.0.3",
    "socks-proxy-agent": "^8.0.4"
  }
}
EOF

# --- 4. Install deps ---
RUN npm install --production

# --- 5. app.js + SOCKS5H FOR .ONION DNS + TEST TARGET ---
RUN mkdir -p etctor && \
    cat > etctor/torrc << 'EOF'
SocksPort 9050
Log notice stdout
DataDirectory /home/debian-tor/.tor
RunAsDaemon 0
EOF

RUN cat > app.js << 'EOF'
const { spawn } = require('child_process');
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const { SocksProxyAgent } = require('socks-proxy-agent');
const http = require('http');
const https = require('https');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 10000;

// === RENDER EXTERNAL CONFIG (NO PORT) ===
const RENDER_HOSTNAME = process.env.RENDER_EXTERNAL_HOSTNAME || 'localhost';
const RENDER_PROTOCOL = (process.env.RENDER_EXTERNAL_URL || '').startsWith('https') ? 'https' : 'http';
const RENDER_BASE_URL = `${RENDER_PROTOCOL}://${RENDER_HOSTNAME}`;
const HEALTH_PATH = '/health';
const FULL_HEALTH_URL = `${RENDER_BASE_URL}${HEALTH_PATH}`;

// === TOR & ONION TARGET (TEST WITH HTTPBIN) ===
const ONION_TARGET = 'http://httpbinorg.ipns.dweb.link/'; // TEST .ONION OVER TOR
// const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/'; // UNCOMMENT WHEN LIVE
const SOCKS_URL = 'socks5h://127.0.0.1:9050'; // ← CRITICAL: 'h' = resolve .onion via Tor
const TORRC_PATH = path.join(__dirname, 'etctor', 'torrc');

let tor, agent;

// === TOR START + MINIMAL torrc ===
function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', TORRC_PATH]);
    tor.on('error', reject);
    tor.on('close', code => {
      if (code !== 0) reject(new Error(`Tor exited: ${code}`));
    });
    resolve();
  });
}

// === WAIT FOR 100% BOOTSTRAP (with fallback) ===
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    let lastPct = -1;
    const timeout = setTimeout(() => {
      console.log('Bootstrap timeout reached. Continuing anyway...');
      resolve();
    }, 90000);

    const check = data => {
      const line = data.toString();
      const match = line.match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (pct > lastPct && pct % 10 === 0) {
          lastPct = pct;
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Tor Bootstraped: ${pct}%`);
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }
        if (pct >= 100) {
          clearTimeout(timeout);
          resolve();
        }
      }
    };

    tor.stdout.on('data', check);
    tor.stderr.on('data', check);
  });
}

// === CREATE SOCKS AGENT WITH DNS OVER TOR ===
function createAgent() {
  agent = new SocksProxyAgent(SOCKS_URL); // 'socks5h://' → .onion DNS via Tor
}

// === EXTERNAL CRON PING via Tor (NO PORT) ===
function startExternalCronPing() {
  const ping = () => {
    const url = new URL(FULL_HEALTH_URL);
    const client = url.protocol === 'https:' ? https : http;
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method: 'GET',
      agent: agent,
      headers: {
        'Host': url.hostname,
        'User-Agent': 'Tor-Health-Ping/1.0',
        'Connection': 'close'
      }
    };

    const req = client.request(options, () => {});
    req.on('error', () => {});
    req.end();
  };

  setTimeout(ping, 15000);
  setInterval(ping, 5 * 60 * 1000);
}

// === PROXY SETUP ===
function setupProxy() {
  const proxyOptions = {
    target: ONION_TARGET,
    changeOrigin: true,
    agent: agent,
    selfHandleResponse: false,
    pathRewrite: { '^/': '' },
    logLevel: 'silent',
    on: {
      error: (err, req, res) => {
        console.log('Proxy error:', err.message);
        if (err.code === 'ENOTFOUND') {
          res.status(502).send('Onion service unreachable or DNS failed via Tor');
        } else {
          res.status(502).send('Bad Gateway');
        }
      }
    }
  };

  const onionProxy = createProxyMiddleware(proxyOptions);

  app.get('/health', (req, res) => res.status(200).send('OK'));
  app.use('/', onionProxy);
}

// === MAIN ===
(async () => {
  try {
    await startTor();
    await waitForBootstrap();
    createAgent();
    setupProxy();
    startExternalCronPing();

    app.listen(PORT, () => {
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log('Tor Web Bridge Running');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Server:        http://localhost:${PORT}`);
      console.log(`Onion Service: ${new URL(ONION_TARGET).host}`);
      console.log(`Base Domain:   ${RENDER_HOSTNAME}`);
      console.log(`Health Check:  ${FULL_HEALTH_URL}`);
      console.log(`External Ping: ${FULL_HEALTH_URL} (via Tor)`);
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });

  } catch (err) {
    console.log('==[ERROR]====================[X]=');
    console.log(err.message);
    console.log('================================');
    process.exit(1);
  }
})();

process.on('SIGTERM', () => tor && tor.kill());
EOF

# --- 6. Expose & Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
  CMD curl -f http://localhost:$PORT/health || exit 1

CMD ["npm", "start"]
