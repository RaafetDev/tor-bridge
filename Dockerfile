# --- ONLY UPDATE app.js IN DOCKERFILE ---
# Replace the app.js section with this:

RUN cat > app.js << 'EOF'
import { spawn } from 'child_process';
import http from 'http';
import https from 'https';

// === DYNAMIC ESM IMPORT ===
const { HttpsProxyAgent } = await import('http-proxy-agent');

const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/';
const PORT = process.env.PORT || 10000;
const SOCKS = 'socks5://127.0.0.1:9050';

let tor, agent, server;

// === TOR LAUNCH (BACKGROUND) ===
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

// === BOOTSTRAP MONITOR ===
async function waitForBootstrap() {
  return new Promise((resolve, reject) => {
    const seen = new Set();
    const timeout = setTimeout(() => reject(new Error('Tor bootstrap timeout')), 180000);

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

// === CRON PING (KEEP ALIVE) ===
function startCronPing() {
  const ping = () => {
    if (!agent) return;
    const req = http.request({
      hostname: '127.0.0.1',
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

// === PROXY HANDLER (GUARDED) ===
function proxyHandler(req, res) {
  if (req.url === '/health') {
    const status = agent ? 'SHADOW CORE V99.2 — LIVE (Tor 100%)' : 'SHADOW CORE V99.2 — STARTING (Tor bootstrapping...)';
    res.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-cache' });
    return res.end(status);
  }

  if (!agent) {
    res.writeHead(503);
    return res.end('Tor not ready');
  }

  try {
    const target = new URL(ONION_TARGET + req.url.replace(/^\/+/, ''));
    const opts = {
      hostname: target.hostname,
      port: target.port || 443,
      path: target.pathname + target.search,
      method: req.method,
      headers: { ...req.headers, host: req.headers.host },
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

// === SHADOW MAIN — NON-BLOCKING START ===
(async () => {
  try {
    console.log('[SHADOW CORE V99.2] Initializing...');

    // === 1. START SERVER IMMEDIATELY (RENDER DETECTS PORT) ===
    server = http.createServer(proxyHandler);
    server.listen(PORT, '0.0.0.0', () => {
      console.log('=====================================');
      console.log('SHΔDØW CORE V99.2 — PORT BOUND');
      console.log(`Bridge LISTENING: 0.0.0.0:${PORT}`);
      console.log('Render will detect in < 10s');
      console.log('=====================================');
    });

    // === 2. LAUNCH TOR IN BACKGROUND ===
    await startTor();
    await waitForBootstrap();
    await createAgent();
    startCronPing();

    console.log('=====================================');
    console.log('SHΔDØW CORE V99.2 — FULLY OPERATIONAL');
    console.log(`Tor Socks5: 127.0.0.1:9050`);
    console.log(`Target: ${ONION_TARGET}`);
    console.log('=====================================');

  } catch (err) {
    console.error('==>[FATAL SHADOW FAILURE]<==');
    console.error(err.stack);
    process.exit(1);
  }
})();

process.on('SIGTERM', () => {
  console.log('[SHUTDOWN] Terminating...');
  tor?.kill();
  server?.close();
  process.exit(0);
});
EOF
