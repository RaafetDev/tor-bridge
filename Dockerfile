# Use slim Node.js 18 base image
FROM node:18-slim

# === Install system dependencies ===
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    wget \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# === Install official playit-agent binary (v0.16.3 - latest stable) ===
RUN curl -fsSL https://github.com/playit-cloud/playit-agent/releases/download/v0.16.3/playit-agent-linux_64 \
    -o /usr/local/bin/playit-agent \
    && chmod +x /usr/local/bin/playit-agent

# === Create app directory ===
WORKDIR /app

# === Create package.json ===
RUN cat > package.json <<'EOF'
{
  "name": "tor-http-proxy",
  "version": "1.0.0",
  "description": "Public Tor-backed HTTP proxy service",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "keywords": ["tor", "proxy", "http", "anonymity"],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "socks-proxy-agent": "^8.0.2"
  }
}
EOF

# === Install Node.js dependencies ===
RUN npm install

# === Create persistent directories ===
RUN mkdir -p /app/tor-data /app/logs /app/playit-data \
    && chmod 700 /app/tor-data /app/playit-data

# === Create startup script for playit persistence ===
RUN cat > start.sh <<'EOF'
#!/bin/bash
set -e

# Create symlink for playit-agent data dir (~/.local/share/playit -> /app/playit-data)
PLAYIT_DATA_DIR="$HOME/.local/share/playit"
if [ ! -L "$PLAYIT_DATA_DIR" ]; then
  mkdir -p "$(dirname "$PLAYIT_DATA_DIR")"
  ln -sf /app/playit-data "$PLAYIT_DATA_DIR"
  echo "Symlinked playit data dir to /app/playit-data for persistence"
else
  echo "Playit data dir already symlinked"
fi

# Start the main app
exec node app.js
EOF
RUN chmod +x start.sh

# === Create app.js (updated for correct playit-agent spawn) ===
RUN cat > app.js <<'EOF'
const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

// === Configuration ===
const PORT = process.env.PORT || 3000;
const SECRET_KEY = process.env.SECRET_KEY || '';
const TOR_SOCKS_PORT = 9050;
const TINYPROXY_PORT = 8888;
const KEEPALIVE_INTERVAL = 5 * 60 * 1000; // 5 minutes

// === Service state ===
const state = {
  torRunning: false,
  tinyproxyRunning: false,
  playitRunning: false,
  proxyHost: 'localhost',
  proxyPort: TINYPROXY_PORT,
  torBootstrapProgress: 0,
  startTime: Date.now()
};

// Process references
let torProcess = null;
let tinyproxyProcess = null;
let playitProcess = null;

// === Utility Functions ===
function log(message) {
  console.log(`[${new Date().toISOString()}] ${message}`);
}

function generateRandomHeaders() {
  const userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
  ];
  return {
    'User-Agent': userAgents[Math.floor(Math.random() * userAgents.length)],
    'X-Request-ID': `keepalive-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    'Accept': 'application/json',
    'Accept-Language': 'en-US,en;q=0.9'
  };
}

// === Tor Configuration and Startup ===
function createTorConfig() {
  const torrcPath = path.join(__dirname, 'tor-data', 'torrc');
  const torDataDir = path.join(__dirname, 'tor-data');

  const torrcContent = `
DataDirectory ${torDataDir}
SocksPort 0.0.0.0:${TOR_SOCKS_PORT}
Log notice stdout
`;

  fs.mkdirSync(torDataDir, { recursive: true });
  fs.writeFileSync(torrcPath, torrcContent.trim());
  log(`Tor config created at ${torrcPath}`);
  return torrcPath;
}

function startTor() {
  return new Promise((resolve, reject) => {
    const torrcPath = createTorConfig();
    log('Starting Tor...');

    torProcess = spawn('tor', ['-f', torrcPath], {
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let bootstrapComplete = false;

    torProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tor] ${output.trim()}`);

      const bootstrapMatch = output.match(/Bootstrapped (\d+)%/);
      if (bootstrapMatch) {
        state.torBootstrapProgress = parseInt(bootstrapMatch[1]);
        log(`Tor bootstrap: ${state.torBootstrapProgress}%`);
      }

      if (output.includes('Bootstrapped 100%') || output.includes('Done')) {
        if (!bootstrapComplete) {
          bootstrapComplete = true;
          state.torRunning = true;
          log('Tor successfully bootstrapped!');
          resolve();
        }
      }
    });

    torProcess.stderr.on('data', (data) => {
      console.error(`[Tor Error] ${data.toString().trim()}`);
    });

    torProcess.on('exit', (code) => {
      log(`Tor process exited with code ${code}`);
      state.torRunning = false;
      if (!bootstrapComplete) {
        reject(new Error(`Tor failed to start (exit code ${code})`));
      }
    });

    setTimeout(() => {
      if (!bootstrapComplete) {
        reject(new Error('Tor bootstrap timeout'));
      }
    }, 60000);
  });
}

// === Tinyproxy Configuration and Startup ===
function createTinyproxyConfig() {
  const configPath = path.join(__dirname, 'tinyproxy.conf');
  const logPath = path.join(__dirname, 'logs', 'tinyproxy.log');

  const configContent = `
Port ${TINYPROXY_PORT}
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
LogFile "${logPath}"
LogLevel Info
MaxClients 100
Allow 0.0.0.0/0
ViaProxyName "TorProxy"
DisableViaHeader No
Upstream socks5 127.0.0.1:${TOR_SOCKS_PORT}
`;

  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  fs.writeFileSync(configPath, configContent.trim());
  log(`Tinyproxy config created at ${configPath}`);
  return configPath;
}

function startTinyproxy() {
  return new Promise((resolve, reject) => {
    const configPath = createTinyproxyConfig();
    log('Starting Tinyproxy...');

    tinyproxyProcess = spawn('tinyproxy', ['-d', '-c', configPath], {
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let started = false;

    const checkStarted = (output) => {
      if (!started && (output.includes('listening') || output.includes('Initializing') || output.includes('Listening on'))) {
        started = true;
        state.tinyproxyRunning = true;
        log('Tinyproxy successfully started!');
        setTimeout(resolve, 2000);
      }
    };

    tinyproxyProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tinyproxy] ${output.trim()}`);
      checkStarted(output);
    });

    tinyproxyProcess.stderr.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tinyproxy] ${output.trim()}`);
      checkStarted(output);
    });

    tinyproxyProcess.on('exit', (code) => {
      log(`Tinyproxy process exited with code ${code}`);
      state.tinyproxyRunning = false;
      if (!started) {
        reject(new Error(`Tinyproxy failed to start (exit code ${code})`));
      }
    });

    setTimeout(() => {
      if (!started) {
        log('Tinyproxy assumed started (timeout fallback)');
        state.tinyproxyRunning = true;
        started = true;
        resolve();
      }
    }, 5000);
  });
}

// === Playit.gg Agent (Corrected: No CLI flags, use env + symlink) ===
function startPlayit() {
  if (!SECRET_KEY) {
    log('No SECRET_KEY provided, skipping playit agent');
    log('Proxy will only be accessible internally at localhost:8888');
    state.playitRunning = false;
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    log('Starting playit-agent (SECRET_KEY via env, data via symlink)...');

    // Spawn with env (includes SECRET_KEY), no CLI args needed
    playitProcess = spawn('playit-agent', [], {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env }  // Passes SECRET_KEY
    });

    let tunnelFound = false;
    let resolved = false;
    let claimDetected = false;

    const resolveOnce = () => {
      if (!resolved) {
        resolved = true;
        state.playitRunning = true;
        resolve();
      }
    };

    playitProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Playit] ${output.trim()}`);

      // Detect claim URL (first-time setup)
      if (!claimDetected && (output.includes('http') && output.includes('claim'))) {
        const claimMatch = output.match(/(https?:\/\/[^ \n]+)/);
        if (claimMatch) {
          log(`🚨 FIRST-TIME SETUP: Visit this claim URL to link agent: ${claimMatch[1]}`);
          claimDetected = true;
        }
      }

      // Detect assigned tunnel
      const match = output.match(/(tcp:\/\/)?([a-z0-9\-]+\.playit\.gg):(\d+)/i);
      if (match && !tunnelFound) {
        state.proxyHost = match[2];
        state.proxyPort = parseInt(match[3]);
        tunnelFound = true;
        log(`✓ Stable Playit tunnel: ${state.proxyHost}:${state.proxyPort}`);
        resolveOnce();
      }
    });

    playitProcess.stderr.on('data', (data) => {
      const output = data.toString();
      console.log(`[Playit] ${output.trim()}`);

      // Check stderr for claim/tunnel too
      if (!claimDetected && output.includes('claim') && output.includes('http')) {
        const claimMatch = output.match(/(https?:\/\/[^ \n]+)/);
        if (claimMatch) {
          log(`🚨 FIRST-TIME SETUP: Visit this claim URL to link agent: ${claimMatch[1]}`);
          claimDetected = true;
        }
      }

      const match = output.match(/(tcp:\/\/)?([a-z0-9\-]+\.playit\.gg):(\d+)/i);
      if (match && !tunnelFound) {
        state.proxyHost = match[2];
        state.proxyPort = parseInt(match[3]);
        tunnelFound = true;
        log(`✓ Stable Playit tunnel: ${state.proxyHost}:${state.proxyPort}`);
        resolveOnce();
      }
    });

    playitProcess.on('exit', (code) => {
      log(`Playit-agent exited with code ${code}`);
      state.playitRunning = false;
      if (!resolved) reject(new Error('playit-agent crashed'));
    });

    // Fallback: Resolve after 15s, but warn if no tunnel/claim
    setTimeout(() => {
      if (!tunnelFound) {
        log('Warning: No tunnel detected yet. Ensure agent is claimed at playit.gg.');
      }
      if (!claimDetected) {
        log('No claim URL seen—agent may already be set up.');
      }
      resolveOnce();
    }, 15000);
  });
}

// === Keepalive System ===
async function keepalive() {
  try {
    const socksAgent = new SocksProxyAgent(`socks5://127.0.0.1:${TOR_SOCKS_PORT}`);
    const headers = generateRandomHeaders();

    const response = await axios.get(`http://localhost:${PORT}/health`, {
      httpAgent: socksAgent,
      httpsAgent: socksAgent,
      headers: headers,
      timeout: 30000
    });

    log(`Keepalive successful: ${response.status}`);
  } catch (error) {
    log(`Keepalive error: ${error.message}`);
  }
}

function startKeepalive() {
  log(`Starting keepalive system (interval: ${KEEPALIVE_INTERVAL / 1000}s)`);
  setInterval(keepalive, KEEPALIVE_INTERVAL);
  setTimeout(keepalive, 30000);
}

// === Express Server ===
const app = express();

const landingPageHTML = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Free Worldwide Tor Proxy</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            text-align: center;
            max-width: 600px;
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 { font-size: 2.5em; margin-bottom: 20px; font-weight: 700; }
        .info-box {
            background: rgba(255, 255, 255, 0.15);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            text-align: left;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            margin: 10px 0;
            font-family: 'Courier New', monospace;
        }
        .label { font-weight: bold; color: #a8d5ff; }
        .value { color: #fff; }
        .warning {
            background: rgba(255, 193, 7, 0.2);
            padding: 15px;
            border-radius: 8px;
            margin-top: 20px;
            font-size: 0.9em;
            border-left: 4px solid #ffc107;
        }
        .note {
            background: rgba(33, 150, 243, 0.2);
            padding: 15px;
            border-radius: 8px;
            margin-top: 10px;
            font-size: 0.85em;
            border-left: 4px solid #2196f3;
            text-align: left;
        }
        a { color: #a8d5ff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Free Worldwide Tor Proxy</h1>
        <p>Anonymous HTTP proxy powered by Tor</p>
       
        <div class="info-box">
            <div class="info-row">
                <span class="label">Type:</span>
                <span class="value">HTTP</span>
            </div>
            <div class="info-row">
                <span class="label">Host:</span>
                <span class="value" id="host">Loading...</span>
            </div>
            <div class="info-row">
                <span class="label">Port:</span>
                <span class="value" id="port">Loading...</span>
            </div>
            <div class="info-row">
                <span class="label">Username:</span>
                <span class="value">free</span>
            </div>
            <div class="info-row">
                <span class="label">Password:</span>
                <span class="value">free</span>
            </div>
        </div>
        <div id="note-container"></div>
        <div class="warning">
            <strong>Legal & Ethical Use Only</strong><br>
            This proxy is for educational and privacy purposes only. Users are responsible for compliance with all applicable laws.
        </div>
        <p style="margin-top: 20px; font-size: 0.9em;">
            <a href="/info">API Endpoint</a> •
            <a href="/health">Health Check</a>
        </p>
    </div>
    <script>
        fetch('/info')
            .then(r => r.json())
            .then(data => {
                document.getElementById('host').textContent = data.host;
                document.getElementById('port').textContent = data.port;
               
                if (data.note) {
                    const noteDiv = document.createElement('div');
                    noteDiv.className = 'note';
                    noteDiv.innerHTML = '<strong>ℹ️ Note:</strong> ' + data.note;
                    document.getElementById('note-container').appendChild(noteDiv);
                }
            })
            .catch(() => {
                document.getElementById('host').textContent = 'Error';
                document.getElementById('port').textContent = 'Error';
            });
    </script>
</body>
</html>
`;

app.get('/', (req, res) => {
  res.setHeader('Content-Type', 'text/html');
  res.send(landingPageHTML);
});

app.get('/info', (req, res) => {
  let host = state.proxyHost;
  let port = state.proxyPort;
  let note = undefined;

  if (host === 'localhost') {
    note = 'Proxy is only accessible within the container. Set SECRET_KEY env var and mount /app/playit-data disk for public access via playit.gg.';
  }

  res.json({
    type: 'http',
    host: host,
    port: port,
    user: 'free',
    pass: 'free',
    note: note
  });
});

app.get('/health', (req, res) => {
  const uptime = Math.floor((Date.now() - state.startTime) / 1000);

  res.json({
    status: 'ok',
    services: {
      tor: state.torRunning,
      tinyproxy: state.tinyproxyRunning,
      playit: state.playitRunning
    },
    torBootstrap: state.torBootstrapProgress,
    uptime: uptime,
    timestamp: new Date().toISOString()
  });
});

// === Main Startup Sequence ===
async function startServices() {
  try {
    log('=== Starting Tor → HTTP Proxy ===');

    log('Step 1: Starting Tor...');
    await startTor();

    log('Step 2: Starting Tinyproxy...');
    await startTinyproxy();

    log('Step 3: Starting Playit agent...');
    await startPlayit();

    log('Step 4: Starting Express server...');
    app.listen(PORT, '0.0.0.0', () => {
      log(`Express server listening on port ${PORT}`);
      log('=== All services started successfully! ===');
      log(`Web UI: http://localhost:${PORT}`);
      log(`Proxy: ${state.proxyHost}:${state.proxyPort}`);

      if (state.proxyHost === 'localhost') {
        log('');
        log('⚠️ PUBLIC ACCESS NOT CONFIGURED');
        log('To enable:');
        log('1. Set SECRET_KEY env var from playit.gg');
        log('2. Add Disk mount: /app/playit-data (for agent persistence)');
        log('3. On first deploy, check logs for claim URL and visit it');
        log('');
      }

      startKeepalive();
    });

  } catch (error) {
    log(`FATAL ERROR: ${error.message}`);
    console.error(error);
    process.exit(1);
  }
}

// === Graceful Shutdown ===
function shutdown() {
  log('Shutting down...');

  if (torProcess) torProcess.kill();
  if (tinyproxyProcess) tinyproxyProcess.kill();
  if (playitProcess) playitProcess.kill();

  setTimeout(() => process.exit(0), 2000);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// === Start Everything ===
startServices();
EOF

# === Create updated README.md ===
RUN cat > README.md <<'EOF'
# Free Worldwide Tor → HTTP Proxy

A single-container app exposing a public HTTP proxy backed by Tor. Runs on free PaaS like Render.com.

## Quick Start (Render.com)

1. **Create Web Service**:
   - Environment: `Docker`
   - Instance Type: `Free`

2. **Add Persistent Disk** (Required for stable tunnel):
   - Name: `playit-data`
   - Mount Path: `/app/playit-data`
   - Size: `1 GB`

3. **Environment Variables**:
   - `SECRET_KEY`: Your playit.gg secret (get from https://playit.gg/account)

4. **Deploy**:
   - First deploy: Watch logs for "FIRST-TIME SETUP: Visit this claim URL..." → Open it in browser, claim the agent, create TCP tunnel for port 8888.
   - Assign a stable tunnel (e.g., `my-tor-proxy.playit.gg:8888`).
   - Future deploys/restarts: Reuses the same tunnel!

## Testing
```bash
# Proxy details
curl https://your-service.onrender.com/info

# Test via proxy
curl -x http://free:free@your-tunnel.playit.gg:8888 http://check.torproject.org
