FROM node:18-slim

RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/playit-cloud/playit-agent/releases/download/v0.16.3/playit-agent-linux_64 \
    -o /usr/local/bin/playit-agent \
    && chmod +x /usr/local/bin/playit-agent

WORKDIR /app

RUN cat > package.json <<'EOF'
{
  "name": "tor-http-proxy",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": { "start": "node app.js" },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "socks-proxy-agent": "^8.0.2"
  }
}
EOF

RUN npm install

RUN mkdir -p /app/tor-data /app/logs /app/playit-data \
    && chmod 700 /app/tor-data /app/playit-data

RUN cat > start.sh <<'EOF'
#!/bin/bash
set -e
PLAYIT_DATA_DIR="$HOME/.local/share/playit"
mkdir -p "$(dirname "$PLAYIT_DATA_DIR")"
[ ! -L "$PLAYIT_DATA_DIR" ] && ln -sf /app/playit-data "$PLAYIT_DATA_DIR"
exec node app.js
EOF
RUN chmod +x start.sh

RUN cat > app.js <<'EOF'
const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

const PORT = process.env.PORT || 3000;
const SECRET_KEY = process.env.SECRET_KEY || '';
const TOR_SOCKS_PORT = 9050;
const TINYPROXY_PORT = 8888;
const KEEPALIVE_INTERVAL = 5 * 60 * 1000;

const state = {
  torRunning: false,
  tinyproxyRunning: false,
  playitRunning: false,
  proxyHost: 'localhost',
  proxyPort: TINYPROXY_PORT,
  torBootstrapProgress: 0,
  startTime: Date.now()
};

let torProcess = null;
let tinyproxyProcess = null;
let playitProcess = null;

function log(msg) { console.log(`[${new Date().toISOString()}] ${msg}`); }

function createTorConfig() {
  const torrcPath = path.join(__dirname, 'tor-data', 'torrc');
  const torDataDir = path.join(__dirname, 'tor-data');
  const torrcContent = `DataDirectory ${torDataDir}\nSocksPort 0.0.0.0:${TOR_SOCKS_PORT}\nLog notice stdout`;
  fs.mkdirSync(torDataDir, { recursive: true });
  fs.writeFileSync(torrcPath, torrcContent.trim());
  return torrcPath;
}

function startTor() {
  return new Promise((resolve, reject) => {
    const torrcPath = createTorConfig();
    torProcess = spawn('tor', ['-f', torrcPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    let done = false;
    torProcess.stdout.on('data', data => {
      const out = data.toString();
      console.log(`[Tor] ${out.trim()}`);
      const m = out.match(/Bootstrapped (\d+)%/);
      if (m) state.torBootstrapProgress = parseInt(m[1]);
      if ((out.includes('100%') || out.includes('Done')) && !done) {
        done = true; state.torRunning = true; resolve();
      }
    });
    torProcess.on('exit', code => { if (!done) reject(new Error('Tor failed')); });
    setTimeout(() => { if (!done) reject(new Error('Tor timeout')); }, 60000);
  });
}

function createTinyproxyConfig() {
  const configPath = path.join(__dirname, 'tinyproxy.conf');
  const logPath = path.join(__dirname, 'logs', 'tinyproxy.log');
  const content = `Port ${TINYPROXY_PORT}\nListen 0.0.0.0\nTimeout 600\nLogFile "${logPath}"\nLogLevel Info\nMaxClients 100\nAllow 0.0.0.0/0\nUpstream socks5 127.0.0.1:${TOR_SOCKS_PORT}`;
  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  fs.writeFileSync(configPath, content.trim());
  return configPath;
}

function startTinyproxy() {
  return new Promise((resolve, reject) => {
    const cfg = createTinyproxyConfig();
    tinyproxyProcess = spawn('tinyproxy', ['-d', '-c', cfg], { stdio: ['ignore', 'pipe', 'pipe'] });
    let started = false;
    const check = out => {
      if (!started && /listening|Listening on/.test(out)) {
        started = true; state.tinyproxyRunning = true; setTimeout(resolve, 2000);
      }
    };
    tinyproxyProcess.stdout.on('data', d => { const o = d.toString(); console.log(`[Tinyproxy] ${o.trim()}`); check(o); });
    tinyproxyProcess.stderr.on('data', d => { const o = d.toString(); console.log(`[Tinyproxy] ${o.trim()}`); check(o); });
    tinyproxyProcess.on('exit', code => { if (!started) reject(new Error('Tinyproxy failed')); });
    setTimeout(() => { if (!started) { state.tinyproxyRunning = true; resolve(); } }, 5000);
  });
}

function startPlayit() {
  if (!SECRET_KEY) { state.playitRunning = false; return Promise.resolve(); }
  return new Promise((resolve, reject) => {
    playitProcess = spawn('playit-agent', [], { stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
    let tunnelFound = false, resolved = false, claimShown = false;
    const resolveOnce = () => { if (!resolved) { resolved = true; state.playitRunning = true; resolve(); } };
    const handle = data => {
      const out = data.toString(); console.log(`[Playit] ${out.trim()}`);
      if (!claimShown && /http.*claim/.test(out)) {
        const m = out.match(/(https?:\/\/[^ \n]+)/); if (m) { console.log(`CLAIM URL: ${m[1]}`); claimShown = true; }
      }
      const m = out.match(/(tcp:\/\/)?([a-z0-9\-]+\.playit\.gg):(\d+)/i);
      if (m && !tunnelFound) { state.proxyHost = m[2]; state.proxyPort = parseInt(m[3]); tunnelFound = true; resolveOnce(); }
    };
    playitProcess.stdout.on('data', handle);
    playitProcess.stderr.on('data', handle);
    playitProcess.on('exit', code => { if (!resolved) reject(new Error('playit-agent crashed')); });
    setTimeout(() => { if (!tunnelFound) console.log('No tunnel yet'); resolveOnce(); }, 15000);
  });
}

async function keepalive() {
  try {
    const agent = new SocksProxyAgent(`socks5://127.0.0.1:${TOR_SOCKS_PORT}`);
    await axios.get(`http://localhost:${PORT}/health`, { httpAgent: agent, httpsAgent: agent, timeout: 30000 });
  } catch (e) {}
}
setInterval(keepalive, KEEPALIVE_INTERVAL); setTimeout(keepalive, 30000);

const app = express();
const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Tor Proxy</title><style>body{font-family:sans-serif;background:#1e3c72;color:#fff;text-align:center;padding:40px;}h1{font-size:2.5em;}.box{background:rgba(255,255,255,0.1);padding:20px;border-radius:10px;margin:20px 0;text-align:left;font-family:monospace;}</style></head><body><h1>Free Tor Proxy</h1><div class="box">Type: <b>HTTP</b><br>Host: <span id="h">...</span><br>Port: <span id="p">...</span><br>User: <b>free</b><br>Pass: <b>free</b></div><div id="n"></div><script>fetch('/info').then(r=>r.json()).then(d=>{document.getElementById('h').innerText=d.host;document.getElementById('p').innerText=d.port;if(d.note){const el=document.createElement('div');el.style='background:rgba(33,150,243,0.2);padding:15px;border-radius:8px;margin-top:10px;border-left:4px solid #2196f3;';el.innerHTML='<b>Note:</b> '+d.note;document.getElementById('n').appendChild(el);}});</script></body></html>`;
app.get('/', (req, res) => res.send(html));
app.get('/info', (req, res) => res.json({
  type: 'http', host: state.proxyHost, port: state.proxyPort,
  user: 'free', pass: 'free',
  note: state.proxyHost === 'localhost' ? 'Set SECRET_KEY + mount /app/playit-data for public access' : undefined
}));
app.get('/health', (req, res) => res.json({
  status: 'ok',
  services: { tor: state.torRunning, tinyproxy: state.tinyproxyRunning, playit: state.playitRunning },
  torBootstrap: state.torBootstrapProgress,
  uptime: Math.floor((Date.now() - state.startTime) / 1000)
}));

async function start() {
  try {
    await startTor();
    await startTinyproxy();
    await startPlayit();
    app.listen(PORT, '0.0.0.0', () => {});
  } catch (e) { process.exit(1); }
}
process.on('SIGTERM', () => { torProcess?.kill(); tinyproxyProcess?.kill(); playitProcess?.kill(); });
process.on('SIGINT', () => process.exit(0));
start();
EOF

EXPOSE 3000
CMD ["./start.sh"]
