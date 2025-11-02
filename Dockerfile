# tor-bridge-render.com - FINAL VERIFIED v3
# Render.com Free Tier | Silent | 0→100% → LIVE | EXTERNAL CRON PING via Tor
# EXPRESS + http-proxy-middleware | Auto torrc | EXTERNAL_HOSTNAME PING

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
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.21.1",
    "http-proxy-middleware": "^3.0.3",
    "http-proxy-agent": "^7.0.2"
  }
}
EOF

# --- 4. Install deps ---
RUN npm install --production

# --- 5. app.js (EXTERNAL CRON PING via Tor + RENDER_EXTERNAL_HOSTNAME) ---
RUN cat > app.js << 'EOF'
const { spawn } = require('child_process');
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const { HttpsProxyAgent } = require('http-proxy-agent').default;
const http = require('http');

const app = express();
const PORT = process.env.PORT || 10000;

// === RENDER EXTERNAL CONFIG ===
const RENDER_HOSTNAME = process.env.RENDER_EXTERNAL_HOSTNAME || 'localhost';
const RENDER_PROTOCOL = process.env.RENDER_EXTERNAL_URL?.startsWith('https') ? 'https' : 'http';
const RENDER_URL = `${RENDER_PROTOCOL}://${RENDER_HOSTNAME}:${PORT}`;
const HEALTH_PATH = '/health';
const FULL_HEALTH_URL = `${RENDER_URL}${HEALTH_PATH}`;

// === TOR & ONION TARGET ===
const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/'; // CHANGE ME
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent;

// === TOR START + HARDENED torrc ===
function startTor() {
  return new Promise((resolve, reject) => {
    const torrc = `
SocksPort 9050
Log notice stdout
DataDirectory /home/debian-tor/.tor
RunAsDaemon 0
ControlPort 9051
CookieAuthentication 1
AvoidDiskWrites 1
HardwareAccel 1
NumCPUs 2
SafeLogging 1
ClientUseIPv4 1
ClientUseIPv6 0
FascistFirewall 1
ReachableAddresses *:80,*:443
EnforceDistinctSubnets 1
EntryNodes {us},{ca},{nl},{de},{fr}
ExitNodes {us},{ca},{nl},{de},{fr}
StrictNodes 1
`.trim();

    require('fs').writeFileSync('/etc/tor/torrc', torrc);

    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.on('close', code => {
      if (code !== 0) reject(new Error(`Tor exited: ${code}`));
    });
    resolve();
  });
}

// === WAIT FOR 100% BOOTSTRAP ===
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    let lastPct = -1;
    const timeout = setTimeout(() => reject(new Error('Bootstrap timeout')), 120000);

    const check = data => {
      const line = data.toString();
      const match = line.match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (pct > lastPct && pct % 10 === 0) {
          lastPct = pct;
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`🔄 Tor Bootstraped: ${pct}%`);
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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

// === CREATE TOR PROXY AGENT ===
function createAgent() {
  agent = new HttpsProxyAgent(SOCKS);
}

// === EXTERNAL CRON PING via Tor to RENDER_EXTERNAL_HOSTNAME/health ===
function startExternalCronPing() {
  const ping = () => {
    const url = new URL(FULL_HEALTH_URL);
    const options = {
      hostname: url.hostname,
      port: url.port || (RENDER_PROTOCOL === 'https' ? 443 : 80),
      path: url.pathname + url.search,
      method: 'GET',
      agent: agent,
      headers: {
        'Host': url.hostname,
        'User-Agent': 'Tor-Health-Ping/1.0',
        'Connection': 'close'
      }
    };

    const client = (RENDER_PROTOCOL === 'https' ? require('https') : http).request(options, () => {});
    client.on('error', () => {});
    client.end();
  };

  // First ping after 15s, then every 5 min
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
        res.status(502).send();
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
      console.log('🚀 Tor Web Bridge Running');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`📍 Server:        http://localhost:${PORT}`);
      console.log(`🧅 Onion Service: ${ONION_TARGET.split('/')[2]}`);
      console.log(`🌐 Base Domain:   ${RENDER_HOSTNAME}`);
      console.log(`💚 Health Check:  ${FULL_HEALTH_URL}`);
      console.log(`🔄 External Ping: ${FULL_HEALTH_URL} (via Tor)`);
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
