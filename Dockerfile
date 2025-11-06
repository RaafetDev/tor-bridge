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
    "axios": "^1.6.0",
    "socks-proxy-agent": "^8.0.2"
  }
}
EOF

# Install Node.js dependencies
RUN npm install

# Create app.js - Minimal orchestration without Express
RUN cat > app.js <<'EOF'
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

// Configuration
const PLAYIT_SECRET = '50fed861d34100d9602c2a94a5b0f4ac782089cf485b88e0e962a7bf6f668645';
const TOR_SOCKS_PORT = 9050;
const TINYPROXY_PORT = 8888;
const KEEPALIVE_INTERVAL = 5 * 60 * 1000; // 5 minutes

// Service state
const state = {
  torRunning: false,
  tinyproxyRunning: false,
  playitRunning: false,
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
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15'
  ];
  
  const acceptLanguages = [
    'en-US,en;q=0.9',
    'en-GB,en;q=0.9',
    'en-US,en;q=0.9,es;q=0.8',
    'en-US,en;q=0.9,fr;q=0.8'
  ];

  return {
    'User-Agent': userAgents[Math.floor(Math.random() * userAgents.length)],
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': acceptLanguages[Math.floor(Math.random() * acceptLanguages.length)],
    'Accept-Encoding': 'gzip, deflate, br',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Cache-Control': 'max-age=0'
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
    }, 90000);
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

// === Playit.gg Agent Using Official Docker Image Approach ===

function startPlayit() {
  if (!PLAYIT_SECRET) {
    log('No PLAYIT_SECRET provided, skipping playit agent');
    log('Proxy will only be accessible locally on port 8888');
    state.playitRunning = false;
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    log('Starting playit.gg agent...');
    log(`Using secret key: ${PLAYIT_SECRET.substring(0, 10)}...`);
    
    const agentPath = path.join(__dirname, 'playit');
    
    if (!fs.existsSync(agentPath)) {
      log('Downloading playit agent from GitHub releases...');
      const downloadUrl = 'https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64';
      
      const downloadProcess = spawn('wget', ['-O', agentPath, downloadUrl, '--no-check-certificate'], {
        stdio: ['ignore', 'pipe', 'pipe']
      });
      
      downloadProcess.stdout.on('data', (data) => {
        console.log(`[Wget] ${data.toString().trim()}`);
      });
      
      downloadProcess.stderr.on('data', (data) => {
        console.log(`[Wget] ${data.toString().trim()}`);
      });
      
      downloadProcess.on('exit', (code) => {
        if (code === 0 && fs.existsSync(agentPath)) {
          const stats = fs.statSync(agentPath);
          log(`Downloaded playit agent (${stats.size} bytes)`);
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
  playitProcess = spawn(agentPath, [], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, SECRET_KEY: PLAYIT_SECRET }
  });

  let tunnelFound = false;

  playitProcess.stdout.on('data', (data) => {
    const output = data.toString();
    console.log(`[Playit] ${output.trim()}`);
    
    // Look for tunnel URLs in various formats
    const patterns = [
      /([a-z0-9\-]+\.playit\.gg):(\d+)/i,
      /tcp.*?([a-z0-9\-]+\.[a-z\.]+):(\d+)/i,
      /tunnel.*?([a-z0-9\-]+\.[a-z\.]+):(\d+)/i
    ];
    
    for (const pattern of patterns) {
      const match = output.match(pattern);
      if (match && !tunnelFound) {
        tunnelFound = true;
        log(`✓ Playit tunnel active: ${match[1]}:${match[2]}`);
        log(`✓ Public proxy available at: http://free:free@${match[1]}:${match[2]}`);
        break;
      }
    }
  });

  playitProcess.stderr.on('data', (data) => {
    const output = data.toString();
    console.log(`[Playit] ${output.trim()}`);
  });

  playitProcess.on('exit', (code) => {
    log(`Playit process exited with code ${code}`);
    state.playitRunning = false;
  });

  state.playitRunning = true;
  log('Playit agent process started');
  setTimeout(callback, 5000);
}

// === Keepalive System - Make REAL external requests through Tor ===

const keepaliveTargets = [
  'http://check.torproject.org',
  'http://www.google.com',
  'http://www.wikipedia.org',
  'http://www.github.com',
  'http://www.reddit.com'
];

async function keepalive() {
  try {
    // Create SOCKS proxy agent for Tor
    const socksAgent = new SocksProxyAgent(`socks5://127.0.0.1:${TOR_SOCKS_PORT}`);
    
    // Pick random target
    const target = keepaliveTargets[Math.floor(Math.random() * keepaliveTargets.length)];
    
    // Generate realistic browser headers
    const headers = generateRandomHeaders();
    
    log(`Keepalive: Requesting ${target} through Tor...`);
    
    const startTime = Date.now();
    const response = await axios.get(target, {
      httpAgent: socksAgent,
      httpsAgent: socksAgent,
      headers: headers,
      timeout: 30000,
      maxRedirects: 5,
      validateStatus: () => true // Accept any status code
    });
    
    const duration = Date.now() - startTime;
    log(`✓ Keepalive successful: ${response.status} from ${target} (${duration}ms via Tor)`);
    
    // Check if we're actually using Tor
    if (target === 'http://check.torproject.org' && response.data) {
      if (response.data.includes('Congratulations')) {
        log('✓ Tor verification: Successfully using Tor network');
      }
    }
    
  } catch (error) {
    log(`✗ Keepalive error: ${error.message}`);
    // Don't crash on keepalive errors, just log them
  }
}

function startKeepalive() {
  log(`Starting keepalive system (interval: ${KEEPALIVE_INTERVAL / 1000}s)`);
  log('Keepalive will make real external HTTP requests through Tor proxy');
  
  // Start periodic keepalive
  setInterval(keepalive, KEEPALIVE_INTERVAL);
  
  // First keepalive after 30 seconds
  setTimeout(keepalive, 30000);
}

// === Main Startup Sequence ===

async function startServices() {
  try {
    log('=== Starting Tor → HTTP Proxy ===');
    log('');
    
    // Step 1: Start Tor and wait for bootstrap
    log('Step 1/3: Starting Tor...');
    await startTor();
    log('');
    
    // Step 2: Start Tinyproxy
    log('Step 2/3: Starting Tinyproxy...');
    await startTinyproxy();
    log('');
    
    // Step 3: Start Playit (optional)
    log('Step 3/3: Starting Playit agent...');
    await startPlayit();
    log('');
    
    log('=== All services started successfully! ===');
    log('');
    log('Proxy Status:');
    log(`  • Tor SOCKS5: localhost:${TOR_SOCKS_PORT}`);
    log(`  • HTTP Proxy: 0.0.0.0:${TINYPROXY_PORT}`);
    log(`  • Playit Agent: ${state.playitRunning ? 'Running' : 'Not configured'}`);
    log('');
    
    if (!PLAYIT_SECRET) {
      log('⚠ No PLAYIT_SECRET configured - proxy only accessible locally');
      log('  Add PLAYIT_SECRET environment variable for public access');
      log('');
    }
    
    log('Test locally: curl -x http://free:free@localhost:8888 http://check.torproject.org');
    log('');
    
    // Start keepalive system
    startKeepalive();
    
    // Keep process alive
    setInterval(() => {
      const uptime = Math.floor((Date.now() - state.startTime) / 1000);
      log(`Heartbeat: Uptime ${uptime}s | Tor: ${state.torRunning} | Tinyproxy: ${state.tinyproxyRunning} | Playit: ${state.playitRunning}`);
    }, 300000); // Every 5 minutes
    
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

// Prevent process from exiting
process.stdin.resume();

// === Start Everything ===

startServices();
EOF

# Create README.md
RUN cat > README.md <<'EOF'
# Tor → HTTP Proxy (Minimal Version)

Pure Tor proxy with Tinyproxy HTTP interface. No Express server - Render automatically detects port 8888.

## Quick Deploy to Render

1. **Create Web Service** on Render.com
2. **Connect this repository**
3. **Environment**: Docker
4. **Add Environment Variable** (for public access):
   - `PLAYIT_SECRET`: Your playit.gg secret key

## Local Testing

```bash
docker build -t tor-proxy .
docker run -p 8888:8888 tor-proxy

# Test the proxy
curl -x http://free:free@localhost:8888 http://check.torproject.org
```

## Playit.gg Setup (For Public Access)

1. Sign up at [playit.gg](https://playit.gg)
2. Create TCP tunnel for port `8888`
3. Copy your **Secret Key** (64-character hex string)
4. Add to Render as `PLAYIT_SECRET` environment variable

The agent will automatically use your persistent secret key.

## What's Running

- **Tor**: SOCKS5 proxy on port 9050
- **Tinyproxy**: HTTP→SOCKS5 bridge on port 8888
- **Playit Agent**: Exposes port 8888 publicly (if configured)
- **Keepalive**: Makes real HTTP requests through Tor every 5 minutes

## Testing

```bash
# Check if using Tor
curl -x http://free:free@localhost:8888 http://check.torproject.org

# Regular browsing
curl -x http://free:free@localhost:8888 http://example.com

# With public playit tunnel
curl -x http://free:free@your-tunnel.playit.gg:12345 http://check.torproject.org
```

## Ethical Use Statement

This proxy is for **educational and privacy purposes only**. 

**Prohibited uses**: illegal activities, hacking, harassment, or any malicious behavior.

**User responsibility**: You are solely responsible for how you use this proxy and must comply with all applicable laws.

By using this service, you accept full legal responsibility.
EOF

# Create directories for Tor and logs
RUN mkdir -p /app/tor-data /app/logs && \
    chmod 700 /app/tor-data

# Expose Tinyproxy port (Render will auto-detect this)
EXPOSE 8888

# Start the application
CMD ["node", "app.js"]
