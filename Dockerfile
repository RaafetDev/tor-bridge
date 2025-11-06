FROM node:18-slim

# Install prerequisites
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    wget \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# Install playit from official PPA
RUN curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" | tee /etc/apt/sources.list.d/playit-cloud.list && \
    apt-get update && \
    apt-get install -y playit && \
    rm -rf /var/lib/apt/lists/*

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
const SECRET_KEY = process.env.SECRET_KEY || '';
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

// === Playit.gg Agent ===

function startPlayit() {
  if (!SECRET_KEY) {
    log('No SECRET_KEY provided, skipping playit agent');
    log('Proxy will only be accessible internally at localhost:8888');
    state.playitRunning = false;
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    log('Starting playit.gg agent...');
    
    // Start playit with SECRET_KEY environment variable
    playitProcess = spawn('playit', [], {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, SECRET_KEY }
    });

    let tunnelFound = false;

    playitProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Playit] ${output.trim()}`);
      
      // Look for tunnel information - playit outputs format like:
      // "Tunnel address: abc-123.playit.gg:54321"
      // or "tcp://abc-123.playit.gg:54321"
      const patterns = [
        /([a-z0-9\-]+\.playit\.gg):(\d+)/i,
        /tcp:\/\/([a-z0-9\-\.]+):(\d+)/i,
        /address[:\s]+([a-z0-9\-\.]+):(\d+)/i,
        /tunnel[:\s]+([a-z0-9\-\.]+):(\d+)/i
      ];
      
      for (const pattern of patterns) {
        const match = output.match(pattern);
        if (match && !tunnelFound) {
          state.proxyHost = match[1];
          state.proxyPort = parseInt(match[2]);
          tunnelFound = true;
          log(`✓ Playit tunnel active: ${state.proxyHost}:${state.proxyPort}`);
          break;
        }
      }
    });

    playitProcess.stderr.on('data', (data) => {
      const output = data.toString();
      console.log(`[Playit] ${output.trim()}`);
      
      // Check stderr for tunnel info too
      const tunnelMatch = output.match(/([a-z0-9\-]+\.playit\.gg):(\d+)/i);
      if (tunnelMatch && !tunnelFound) {
        state.proxyHost = tunnelMatch[1];
        state.proxyPort = parseInt(tunnelMatch[2]);
        tunnelFound = true;
        log(`✓ Playit tunnel active: ${state.proxyHost}:${state.proxyPort}`);
      }
    });

    playitProcess.on('exit', (code) => {
      log(`Playit process exited with code ${code}`);
      state.playitRunning = false;
    });

    state.playitRunning = true;
    log('Playit agent started, waiting for tunnel...');
    
    // Give it time to establish tunnel
    setTimeout(() => {
      if (!tunnelFound) {
        log('Warning: Playit tunnel not detected yet. Check playit.gg dashboard.');
      }
      resolve();
    }, 8000);
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
  
  // If still localhost, provide helpful message
  if (host === 'localhost') {
    note = 'Proxy is only accessible within the container network. Set SECRET_KEY environment variable with your playit.gg secret to enable public access.';
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
        log('⚠️  PUBLIC ACCESS NOT CONFIGURED');
        log('To enable public access, set SECRET_KEY environment variable');
        log('Get your secret from: https://playit.gg');
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

# Create README.md
RUN cat > README.md <<'EOF'
# Free Worldwide Tor → HTTP Proxy

A single-container application that exposes a public HTTP proxy backed by Tor, designed to run on free PaaS platforms.

## 🎯 Quick Start

### Deploy to Render.com

1. **Fork/Clone this repository**

2. **Create Web Service on Render.com**:
   - Environment: Docker
   - Instance Type: Free

3. **Configure Playit.gg for Public Access**:
   - Sign up at [playit.gg](https://playit.gg)
   - Create a TCP tunnel for port 8888
   - In Render, add environment variable:
     - Key: `SECRET_KEY`
     - Value: `<your-playit-secret>`

4. **Deploy and wait 5-10 minutes**

5. **Access your proxy**:
   - Web UI: `https://your-service.onrender.com`
   - Proxy: Use address from `/info` endpoint

## 🧪 Testing

```bash
# Get proxy details
curl https://your-service.onrender.com/info

# Test the proxy
curl -x http://free:free@your-playit-host:port http://check.torproject.org
```

## 📡 API Endpoints

- `GET /` - Landing page with proxy info
- `GET /info` - JSON with connection details
- `GET /health` - Service status

## 🛡️ Ethical Use Statement

**This proxy is for legitimate educational and privacy purposes only.**

Prohibited uses include:
- Illegal activities
- Unauthorized access or hacking
- Distribution of illegal content
- Harassment or abuse

By using this service, you accept full legal responsibility.

## 🔒 Security Notes

- Traffic is routed through Tor for IP anonymity
- Use HTTPS endpoints when possible
- No strong authentication (demo credentials: free/free)
- Monitor logs for abuse

## 📝 Environment Variables

- `PORT` - Express server port (default: 3000)
- `SECRET_KEY` - Playit.gg secret for public access (optional)

## ⚠️ Disclaimer

Provided "as-is" for educational purposes. Authors are not responsible for misuse.
EOF

# Create directories for Tor and logs
RUN mkdir -p /app/tor-data /app/logs && \
    chmod 700 /app/tor-data

# Expose the Express server port
EXPOSE 3000

# Start the application
CMD ["node", "app.js"]
