# tor-bridge-render.com - SHADOW CORE V107
# SINGLE FILE | CSP BYPASS | FULL ONION + ASSETS

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
  "name": "tor-bridge-v107",
  "version": "107.0.0",
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

# --- 7. app.js — V107 (CSP BYPASS + ASSET PROXY) ---
RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import fetch from 'node-fetch';
import { SocksProxyAgent } from 'socks-proxy-agent';

// === CONFIG ===
const ONION_URL = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion';
const PROXY_HOST = 'tor-bridge.onrender.com';
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
          console.log(`[V107] Bootstrap: ${pct}%`);
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

// === REWRITE HTML + CSP BYPASS ===
function rewriteHTML(html) {
  return html
    .replace(/<head>/i, `<head>
      <meta http-equiv="Content-Security-Policy" content="
        default-src 'self' https: data: blob:;
        script-src 'self' 'unsafe-inline' 'unsafe-eval' https: data: blob:;
        style-src 'self' 'unsafe-inline' https: data:;
        img-src 'self' data: https:;
        font-src 'self' data: https:;
        connect-src 'self' https:;
        frame-src 'self' https:;
        media-src 'self' https:;
        object-src 'none';
      ">
    `)
    .replace(/(src|href)=["']([^"']+)["']/gi, (match, attr, url) => {
      if (url.startsWith('http') || url.startsWith('//') || url.startsWith('data:')) return match;
      const abs = url.startsWith('/') ? `https://${PROXY_HOST}${url}` : `https://${PROXY_HOST}/${url}`;
      return `${attr}="${abs}"`;
    });
}

// === PROXY HANDLER (FULL ASSET PROXY + CSP) ===
async function proxyHandler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('V107 LIVE');
  }

  const path = req.url === '/' ? '' : req.url;
  const targetUrl = `${ONION_URL}${path}`;

  try {
    const headers = {
      ...req.headers,
      host: new URL(ONION_URL).host,
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
      'accept': '*/*',
      'accept-encoding': 'gzip, deflate, br',
      'sec-fetch-dest': 'document',
      'sec-fetch-mode': 'navigate',
      'sec-fetch-site': 'none'
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

    // CSP Bypass + Asset Proxy
    if (response.headers.get('content-type')?.includes('text/html')) {
      let html = await response.text();
      html = rewriteHTML(html);
      res.writeHead(response.status, {
        ...respHeaders,
        'content-type': 'text/html',
        'content-security-policy': ''  // Strip original CSP
      });
      res.end(html);
      return;
    }

    // Proxy all other assets
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
    console.log('[V107] Starting...');
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
      console.log('SHΔDØW CORE V107 — CSP BYPASS LIVE');
      console.log(`Bridge: https://${PROXY_HOST}`);
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
