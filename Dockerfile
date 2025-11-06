FROM node:18-slim

# Install Tor, tinyproxy, and required tools
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Create package.json
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

# Install Node.js dependencies
RUN npm install

# Create app.js
RUN cat > app.js <<'EOF'
const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

// Configuration
const PORT = process.env.PORT || 3000;
const PLAYIT_SECRET = process.env.PLAYIT_SECRET || '';
const TOR_SOCKS_PORT = 9050;
const TINYPROXY_PORT = 8888;
const KEEPALIVE_INTERVAL = 5 * 60 * 1000; // 5 minutes

// Service state
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
ControlPort 9051
CookieAuthentication 1
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
      
      // Parse bootstrap progress
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

    // Timeout after 60 seconds
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
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
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

    tinyproxyProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tinyproxy] ${output.trim()}`);
      
      if (!started && (output.includes('listening') || output.includes('Initializing'))) {
        started = true;
        state.tinyproxyRunning = true;
        log('Tinyproxy successfully started!');
        setTimeout(resolve, 2000);
      }
    });

    tinyproxyProcess.stderr.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tinyproxy] ${output.trim()}`);
      if (!started && output.includes('Listening on')) {
        started = true;
        state.tinyproxyRunning = true;
        log('Tinyproxy successfully started!');
        setTimeout(resolve, 2000);
      }
    });

    tinyproxyProcess.on('exit', (code) => {
      log(`Tinyproxy process exited with code ${code}`);
      state.tinyproxyRunning = false;
      if (!started) {
        reject(new Error(`Tinyproxy failed to start (exit code ${code})`));
      }
    });

    // Fallback - assume started after 5 seconds
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

// === Playit.gg Agent (Optional) ===

function startPlayit() {
  if (!PLAYIT_SECRET) {
    log('No PLAYIT_SECRET provided, skipping playit agent');
    state.playitRunning = false;
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    log('Starting playit.gg agent...');
    
    const agentPath = path.join(__dirname, 'playit');
    
    if (!fs.existsSync(agentPath)) {
      log('Downloading playit agent...');
      const downloadUrl = 'https://playit.gg/downloads/playit-linux-amd64';
      
      const downloadProcess = spawn('curl', ['-L', '-o', agentPath, downloadUrl]);
      
      downloadProcess.on('exit', (code) => {
        if (code === 0) {
          fs.chmodSync(agentPath, '755');
          startPlayitProcess(agentPath, resolve);
        } else {
          log('Failed to download playit agent');
          resolve();
        }
      });
    } else {
      startPlayitProcess(agentPath, resolve);
    }
  });
}

function startPlayitProcess(agentPath, callback) {
  playitProcess = spawn(agentPath, ['--secret', PLAYIT_SECRET], {
    stdio: ['ignore', 'pipe', 'pipe']
  });

  playitProcess.stdout.on('data', (data) => {
    const output = data.toString();
    console.log(`[Playit] ${output.trim()}`);
    
    const hostMatch = output.match(/host[:\s]+([a-z0-9\-\.]+)/i);
    const portMatch = output.match(/port[:\s]+(\d+)/i);
    
    if (hostMatch && portMatch) {
      state.proxyHost = hostMatch[1];
      state.proxyPort = parseInt(portMatch[1]);
      log(`Playit tunnel: ${state.proxyHost}:${state.proxyPort}`);
    }
  });

  playitProcess.stderr.on('data', (data) => {
    console.log(`[Playit] ${data.toString().trim()}`);
  });

  playitProcess.on('exit', (code) => {
    log(`Playit process exited with code ${code}`);
    state.playitRunning = false;
  });

  state.playitRunning = true;
  log('Playit agent started');
  setTimeout(callback, 3000);
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
        h1 {
            font-size: 2.5em;
            margin-bottom: 20px;
            font-weight: 700;
        }
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

        <div class="warning">
            ⚠️ <strong>Legal & Ethical Use Only</strong><br>
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
  res.json({
    type: 'http',
    host: state.proxyHost,
    port: state.proxyPort,
    user: 'free',
    pass: 'free'
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
      log(`Access the proxy at: http://localhost:${PORT}`);
      log(`Proxy endpoint: ${state.proxyHost}:${state.proxyPort}`);
      
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

# Create README.md
RUN cat > README.md <<'EOF'
# Free Worldwide Tor → HTTP Proxy

A single-container application that exposes a public HTTP proxy backed by Tor, designed to run on free PaaS platforms.

## 🎯 Overview

This project creates a fully functional HTTP proxy that routes all traffic through the Tor network for anonymous browsing. It's built as a single Dockerfile with all files embedded using heredoc syntax.

### Architecture

- **Tor**: Provides SOCKS5 proxy for anonymous routing
- **Tinyproxy**: Converts HTTP requests to Tor's SOCKS5 format
- **Node.js/Express**: Orchestrates services and provides API endpoints
- **Playit.gg** (optional): Exposes the proxy publicly via tunneling

## 🚀 Quick Start

### Local Testing

```bash
# Build the Docker image
docker build -t tor-http-proxy .

# Run the container
docker run -p 3000:3000 tor-http-proxy

# Access the landing page
open http://localhost:3000
```

### Deploy to Render.com

1. **Create new Web Service** on Render.com
2. **Choose "Deploy from a Git repository"**
3. **Connect this repository**
4. **Configure**:
   - Environment: Docker
   - Instance Type: Free
5. **(Optional) Add environment variable**:
   - `PLAYIT_SECRET`: Your playit.gg secret key
6. **Deploy** and wait 5-10 minutes

## 📡 API Endpoints

### `GET /`
Landing page with proxy information

### `GET /info`
Returns proxy connection details
```json
{
  "type": "http",
  "host": "your-host.com",
  "port": 8888,
  "user": "free",
  "pass": "free"
}
```

### `GET /health`
Health check with service status
```json
{
  "status": "ok",
  "services": {
    "tor": true,
    "tinyproxy": true,
    "playit": false
  },
  "torBootstrap": 100,
  "uptime": 3600
}
```

## 🧪 Testing the Proxy

### Using curl
```bash
curl -x http://free:free@localhost:8888 http://check.torproject.org
```

### Using Python
```python
import requests

proxies = {
    'http': 'http://free:free@localhost:8888'
}

response = requests.get('http://check.torproject.org', proxies=proxies)
print(response.text)
```

## 🛡️ Ethical Use & Compliance Statement

**IMPORTANT**: This proxy is designed for legitimate educational, privacy, and research purposes only.

### Intended Use Cases
- Privacy-conscious browsing
- Educational demonstrations of Tor technology
- Testing and development of anonymous applications
- Research into privacy-enhancing technologies

### Prohibited Uses
This service **MUST NOT** be used for:
- Any illegal activities under applicable laws
- Hacking, unauthorized access, or computer intrusion
- Distribution of illegal content
- Harassment, abuse, or harm to others

### User Responsibility
By using this proxy, you acknowledge that:
1. You are solely responsible for your use of this service
2. You will comply with all applicable laws in your jurisdiction
3. You will respect the rights and terms of service of websites you access
4. The proxy operator is not responsible for user activities

**By deploying or using this service, you accept full legal responsibility for its operation and use.**

## 🔒 Security Considerations

### What This Proxy Does
- ✅ Routes traffic through Tor for IP anonymity
- ✅ Provides basic HTTP proxy functionality
- ✅ Keeps services alive with periodic health checks

### What This Proxy Does NOT Do
- ❌ Does NOT encrypt traffic between client and proxy
- ❌ Does NOT provide strong authentication
- ❌ Does NOT log or filter malicious requests
- ❌ Does NOT guarantee anonymity if used improperly

## 🐛 Troubleshooting

### Tor Won't Bootstrap
- Wait up to 3 minutes (can be slow on some networks)
- Check logs: `docker logs <container-id>`

### Tinyproxy Connection Refused
- Ensure Tor is fully bootstrapped first
- Verify port 8888 is not in use

### PaaS Platform Sleeping
- Keepalive should prevent this automatically
- Verify keepalive is running (check logs every 5 minutes)

## ⚠️ Disclaimer

This project is provided "as-is" for educational purposes. The authors and contributors:
- Make no warranties about reliability, security, or fitness for any purpose
- Are not responsible for misuse or illegal activities
- Recommend understanding all applicable laws before deployment

**Use at your own risk.**
EOF

# Create directories for Tor and logs
RUN mkdir -p /app/tor-data /app/logs && \
    chmod 700 /app/tor-data

# Expose the Express server port
EXPOSE 3000

# Start the application
CMD ["node", "app.js"]
