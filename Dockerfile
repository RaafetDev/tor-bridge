FROM node:20-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/tor /var/log/tor && \
    chown debian-tor:debian-tor /var/lib/tor /var/log/tor

RUN cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
Log notice stdout
DataDirectory /var/lib/tor
RunAsDaemon 0
ControlPort 9051
CookieAuthentication 1
EOF

USER debian-tor
WORKDIR /app

RUN cat > package.json << 'EOF'
{
  "name": "tor-bridge-v108",
  "version": "108.0.0",
  "type": "module",
  "scripts": { "start": "node app.js" },
  "dependencies": {
    "node-fetch": "^3.3.2",
    "socks-proxy-agent": "^8.0.4"
  }
}
EOF

RUN npm install --production

RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import fetch from 'node-fetch';
import { SocksProxyAgent } from 'socks-proxy-agent';

const ONION_URL = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion';
const PROXY_HOST = 'tor-bridge.onrender.com';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5h://127.0.0.1:9050';

let tor, agent;

function startTor() {
  return new Promise((resolve, reject) => {
    tor = spawn('tor', ['-f', '/etc/tor/torrc']);
    tor.on('error', reject);
    tor.stdout.on('data', () => {});
    tor.stderr.on('data', () => {});
    tor.on('close', code => code !== 0 && reject(new Error('Tor died')));
    setTimeout(resolve, 3000);
  });
}

function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Timeout')), 180000);
    const check = data => {
      const match = data.toString().match(/Bootstrapped\s+(\d+)%/);
      if (match) {
        const pct = parseInt(match[1], 10);
        if (!seen.has(pct)) {
          seen.add(pct);
          if (pct === 100) {
            clearTimeout(timeout);
            resolve();
          }
        }
      }
    };
    tor.stdout.on('data', check);
    tor.stderr.on('data', check);
  });
}

function createAgent() {
  agent = new SocksProxyAgent(SOCKS);
}

function startCronPing() {
  const ping = () => {
    http.request({ hostname: '127.0.0.1', port: PORT, path: '/health', method: 'GET' }, () => {}).end();
  };
  setInterval(ping, 240000);
  setTimeout(ping, 15000);
}

function rewriteHTML(html) {
  return html
    .replace(/<head>/i, `<head>
      <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval' data: blob:;">
    `)
    .replace(/(src|href)=["']([^"']+)["']/gi, (m, attr, url) => {
      if (/^data:|^blob:|^(https?:)?\/\//i.test(url)) return m;
      const abs = url.startsWith('/') ? `https://${PROXY_HOST}${url}` : `https://${PROXY_HOST}/${url}`;
      return `${attr}="${abs}"`;
    })
    .replace(/url\(["']?([^"')]+)["']?\)/gi, (m, u) => {
      if (/^data:|^#/i.test(u)) return m;
      const abs = u.startsWith('/') ? `https://${PROXY_HOST}${u}` : `https://${PROXY_HOST}/${u}`;
      return `url("${abs}")`;
    });
}

async function proxyHandler(req, res) {
  if (req.url === '/health') return res.end('V108 LIVE');

  const path = req.url === '/' ? '' : req.url;
  const targetUrl = `${ONION_URL}${path}`;

  try {
    const headers = {
      ...req.headers,
      host: new URL(ONION_URL).host,
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    };
    delete headers['connection'];
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

    const respHeaders = Object.fromEntries(
      [...response.headers.entries()].filter(([k]) => !['transfer-encoding', 'content-encoding'].includes(k))
    );

    if (response.headers.get('content-type')?.includes('text/html')) {
      let html = await response.text();
      html = rewriteHTML(html);
      res.writeHead(response.status, { ...respHeaders, 'content-type': 'text/html', 'content-security-policy': '' });
      return res.end(html);
    }

    if (response.headers.get('content-type')?.includes('application/json')) {
      let json = await response.text();
      json = json.replace(/(https?:)?\/\/[^"']+/g, match => {
        if (match.includes(PROXY_HOST)) return match;
        return `https://${PROXY_HOST}${new URL(match).pathname}`;
      });
      res.writeHead(response.status, { ...respHeaders, 'content-type': 'application/json' });
      return res.end(json);
    }

    res.writeHead(response.status, respHeaders);
    response.body.pipe(res);

  } catch (err) {
    if (!res.headersSent) res.writeHead(502);
    res.end('Bad Gateway');
  }
}

(async () => {
  try {
    await startTor();
    await waitForBootstrap();
    createAgent();
    startCronPing();

    const server = http.createServer((req, res) => {
      req.on('error', () => res.end());
      res.on('error', () => {});
      proxyHandler(req, res).catch(() => {});
    });

    server.listen(PORT, '0.0.0.0');

  } catch (err) {
    process.exit(1);
  }
})();
EOF

EXPOSE 10000
HEALTHCHECK --interval=30s --timeout=10s --start-period=200s --retries=5 CMD curl -f http://localhost:10000/health || exit 1
CMD ["node", "app.js"]
