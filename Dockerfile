# tor-bridge-render.com - SHADOW CORE V102
# SINGLE FILE | 400/502 FIXED | HTTPS ONION VIA CONNECT

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
  "name": "tor-bridge-v102",
  "version": "102.0.0",
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

# --- 7. app.js — V102 (CONNECT TUNNEL + HTTPS ONION) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import { SocksProxyAgent } from 'socks-proxy-agent';
import { URL } from 'url';

// === CONFIG ===
const ONION_HOST = 'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion';
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
          console.log(`[V102] Bootstrap: ${pct}%`);
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

// === PROXY HANDLER (CONNECT + HTTPS) ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V102 LIVE');
  }

  const path = req.url.replace(/^\/+/, '') || '/';
  const target = `https://${ONION_HOST}/${path}`;

  const url = new URL(target);
  const opts = {
    method: 'CONNECT',
    path: `${url.hostname}:443`,
    agent,
    headers: { host: url.hostname }
  };

  const connectReq = http.request(opts);

  connectReq.on('connect', (proxyRes, socket) => {
    if (proxyRes.statusCode !== 200) {
      res.writeHead(502);
      return res.end('Tunnel failed');
    }

    // Now send HTTPS request over tunnel
    const httpsReq = [
      `${req.method} ${url.pathname}${url.search} HTTP/1.1`,
      `Host: ${url.hostname}`,
      'Connection: close',
      ...Object.entries(req.headers)
        .filter(([k]) => !['host', 'connection'].includes(k.toLowerCase()))
        .map(([k, v]) => `${k}: ${v}`),
      '',
      ''
    ].join('\r\n');

    socket.write(httpsReq);

    // Pipe body
    req.pipe(socket);

    // Pipe response
    let response = '';
    socket.on('data', chunk => {
      response += chunk.toString();
      const headersEnd = response.indexOf('\r\n\r\n');
      if (headersEnd !== -1 && !res.headersSent) {
        const headerPart = response.slice(0, headersEnd);
        const bodyPart = response.slice(headersEnd + 4);
        const statusLine = headerPart.split('\r\n')[0];
        const statusMatch = statusLine.match(/HTTP\/1\.[01]\s+(\d+)/);
        const status = statusMatch ? parseInt(statusMatch[1]) : 502;
        const headers = {};
        headerPart.split('\r\n').slice(1).forEach(line => {
          const [k, v] = line.split(': ');
          if (k && v) headers[k.toLowerCase()] = v;
        });
        delete headers['transfer-encoding'];
        res.writeHead(status, headers);
        res.write(bodyPart);
      } else if (res.headersSent) {
        res.write(chunk);
      }
    });

    socket.on('end', () => res.end());
    socket.on('error', () => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
  });

  connectReq.on('error', () => {
    if (!res.headersSent) res.writeHead(502);
    res.end('Bad Gateway');
  });

  connectReq.end();
}

// === MAIN ===
(async () => {
  try {
    console.log('[V102] Starting...');
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    const server = http.createServer((req, res) => {
      req.on('error', () => res.end());
      res.on('error', () => {});
      proxyHandler(req, res);
    });

    server.listen(PORT, '0.0.0.0', () => {
      console.log('================================');
      console.log('SHΔDØW CORE V102 — 100% LIVE');
      console.log(`Bridge: http://0.0.0.0:${PORT}`);
      console.log(`Target: https://${ONION_HOST}/`);
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
