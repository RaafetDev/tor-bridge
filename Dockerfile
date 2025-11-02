# tor-bridge-render.com - SINGLE FILE DOCKER
# Render.com Free Tier | <60s build | apt tor | Node.js + SOCKS5
# All traffic → .onion via Tor | No external files | EOF-free

FROM node:20-slim

# --- 1. Install Tor (lightweight, fast) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/tor && \
    chown debian-tor:debian-tor /var/run/tor

# --- 2. Copy torrc via inline HEREDOC (no external file) ---
RUN cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
ControlPort 9051
Log notice stdout
DataDirectory /var/lib/tor
PidFile /var/run/tor/tor.pid
RunAsDaemon 0
EOF

# --- 3. Project setup ---
WORKDIR /app

# package.json (inline)
RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": { "start": "node app.js" },
  "dependencies": {
    "socks-proxy-agent": "^8.0.4",
    "http-proxy-agent": "^7.0.2"
  }
}
EOF

# Install deps
RUN npm install --production

# --- 4. app.js (inline, full bridge) ---
RUN cat > app.js << 'EOF'
const { spawn } = require('child_process');
const net = require('net');
const http = require('http');
const https = require('https');
const { SocksProxyAgent } = require('socks-proxy-agent');
const { HttpsProxyAgent } = require('http-proxy-agent');

const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/'; // CHANGE ME
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent, httpsAgent;

function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.stdout.on('data', d => {
      const out = d.toString();
      console.log('Tor:', out);
      if (out.includes('Bootstrapped 100%')) resolve();
    });
    tor.stderr.on('data', d => console.error('Tor ERR:', d.toString()));
    tor.on('close', c => console.log('Tor exited:', c));
  });
}

function waitForSocks() {
  return new Promise(r => {
    const i = setInterval(() => {
      net.connect(9050, '127.0.0.1', () => { clearInterval(i); r(); }).on('error', () => {});
    }, 1000);
  });
}

function createAgents() {
  agent = new SocksProxyAgent(SOCKS);
  httpsAgent = new HttpsProxyAgent(SOCKS);
}

function proxyHandler(req, res) {
  const url = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
  const opts = {
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname + url.search,
    method: req.method,
    headers: req.headers,
    agent: httpsAgent
  };

  const client = https.request(opts, proxyRes => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  req.pipe(client);
  client.on('error', e => {
    console.error('Proxy error:', e.message);
    res.statusCode = 502;
    res.end('Tor bridge error');
  });
}

async function main() {
  try {
    await startTor();
    await waitForSocks();
    createAgents();
    http.createServer(proxyHandler).listen(PORT, () => {
      console.log(`Tor Bridge LIVE on port ${PORT}`);
      console.log(`→ All traffic → ${ONION_TARGET}`);
    });
  } catch (e) {
    console.error('Startup failed:', e);
    process.exit(1);
  }
}

main();
process.on('SIGTERM', () => tor && tor.kill());
EOF

# --- 5. Expose & Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD netstat -ln | grep -q 9050 || exit 1

CMD ["npm", "start"]
