# tor-bridge-render.com - FULL SINGLE FILE
# Render.com Free Tier | <60s build | Debian tor | Silent logs
# Only: 0→100% → LIVE or ERROR

FROM node:20-slim

# --- 1. Install Tor (Debian package) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Create torrc + safe DataDirectory ---
RUN mkdir -p /home/debian-tor/.tor && \
    chown debian-tor:debian-tor /home/debian-tor/.tor && \
    cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
ControlPort 9051
Log notice stdout
DataDirectory /home/debian-tor/.tor
RunAsDaemon 0
EOF

# --- 3. Switch to debian-tor user ---
USER debian-tor
WORKDIR /home/debian-tor/app

# --- 4. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": { "  start": "node app.js" },
  "dependencies": {
    "http-proxy-agent": "^7.0.2"
  }
}
EOF

# --- 5. Install deps ---
RUN npm install --production

# --- 6. app.js (SILENT, ONLY 0→100% & LIVE/ERROR) ---
RUN cat > app.js << 'EOF'
const { spawn } = require('child_process');
const http = require('https');
const { HttpsProxyAgent } = require('http-proxy-agent');

const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/'; // CHANGE ME
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent;

// Start Tor silently
function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.on('close', code => { if (code !== 0) reject(new Error(`Tor died: ${code}`)); });
    resolve();
  });
}

// Wait for 100% bootstrap (print only 0→100%, no duplicates)
function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Bootstrap timeout')), 60000);

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
    tor.on('close', () => clearTimeout(timeout));
  });
}

// Create SOCKS agent
function createAgent() {
  agent = new HttpsProxyAgent(SOCKS);
}

// Proxy all requests to .onion
function proxyHandler(req, res) {
  const url = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
  const opts = {
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname + url.search,
    method: req.method,
    headers: req.headers,
    agent
  };

  const client = http.request(opts, proxyRes => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  req.pipe(client);
  client.on('error', () => {
    res.statusCode = 502;
    res.end();
  });
}

// Main
(async () => {
  try {
    await startTor();
    await waitForBootstrap();
    createAgent();

    console.log('================================');
    console.log('Tor Socks5 LIVE on: 127.0.0.1:9050');
    console.log(`Tor Bridge LIVE on port: ${PORT}`);
    console.log(`→ All traffic → ${ONION_TARGET}`);
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
  CMD curl -f http://localhost:$PORT || exit 1

CMD ["npm", "start"]
