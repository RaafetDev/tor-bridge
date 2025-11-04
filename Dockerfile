FROM node:18-bullseye

# Install Tor and Tinyproxy
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create package.json
RUN cat > package.json << 'EOF'
{
  "name": "tor-proxy-render",
  "version": "1.0.0",
  "description": "Public HTTP Tor Proxy with Ngrok",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "socks-proxy-agent": "^8.0.2",
    "node-cron": "^3.0.3",
    "ngrok": "^5.0.0-beta.2",
    "http-proxy": "^1.18.1"
  }
}
EOF

# Install dependencies
RUN npm install

# Create Tor configuration
RUN cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
ControlPort 9051
CookieAuthentication 0
DataDirectory /var/lib/tor
Log notice stdout
EOF

# Create Tinyproxy configuration
RUN cat > /etc/tinyproxy/tinyproxy.conf << 'EOF'
User nobody
Group nogroup
Port 8888
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
Allow 127.0.0.1
ViaProxyName "tinyproxy"
DisableViaHeader Yes
BasicAuth toruser torpass123
Upstream socks5 127.0.0.1:9050
EOF

# Create main server application
RUN cat > server.js << 'EOF'
const express = require('express');
const { spawn } = require('child_process');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');
const cron = require('node-cron');
const ngrok = require('ngrok');
const httpProxy = require('http-proxy');

const app = express();
const PORT = process.env.PORT || 3000;
const LOGIN_TOKEN = process.env.LOGIN_TOKEN || 'secret123';

let torProcess = null;
let tinyproxyProcess = null;
let ngrokUrl = null;
let torBootstrapProgress = 0;
let isReady = false;

const proxy = httpProxy.createProxyServer({});

// Start Tor
function startTor() {
  return new Promise((resolve, reject) => {
    console.log('🧅 Starting Tor...');
    torProcess = spawn('tor', ['-f', '/etc/tor/torrc']);

    torProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tor] ${output}`);

      const bootstrapMatch = output.match(/Bootstrapped (\d+)%/);
      if (bootstrapMatch) {
        torBootstrapProgress = parseInt(bootstrapMatch[1]);
        console.log(`🔄 Tor bootstrap progress: ${torBootstrapProgress}%`);

        if (torBootstrapProgress === 100) {
          console.log('✅ Tor is fully bootstrapped!');
          resolve();
        }
      }
    });

    torProcess.stderr.on('data', (data) => {
      console.error(`[Tor Error] ${data}`);
    });

    torProcess.on('close', (code) => {
      console.log(`Tor process exited with code ${code}`);
      if (code !== 0) reject(new Error('Tor failed to start'));
    });
  });
}

// Start Tinyproxy
function startTinyproxy() {
  console.log('🔧 Starting Tinyproxy...');
  tinyproxyProcess = spawn('tinyproxy', ['-d', '-c', '/etc/tinyproxy/tinyproxy.conf']);

  tinyproxyProcess.stdout.on('data', (data) => {
    console.log(`[Tinyproxy] ${data}`);
  });

  tinyproxyProcess.stderr.on('data', (data) => {
    console.log(`[Tinyproxy] ${data}`);
  });

  tinyproxyProcess.on('close', (code) => {
    console.log(`Tinyproxy process exited with code ${code}`);
  });
}

// Start Ngrok
async function startNgrok() {
  console.log('🌐 Starting Ngrok tunnel...');
  try {
    ngrokUrl = await ngrok.connect({
      addr: 8888,
      proto: 'http',
      bind_tls: false
    });
    console.log(`✅ Ngrok tunnel established: ${ngrokUrl}`);
    isReady = true;
  } catch (error) {
    console.error('❌ Failed to start Ngrok:', error);
  }
}

// Middleware for authentication
function requireAuth(req, res, next) {
  const token = req.headers['authorization'] || req.headers['login'];
  if (token === LOGIN_TOKEN) {
    next();
  } else {
    res.status(401).json({ error: 'Unauthorized' });
  }
}

// Routes
app.get('/', (req, res) => {
  res.json({
    status: 'running',
    tor: {
      running: torProcess !== null,
      bootstrapProgress: torBootstrapProgress
    },
    tinyproxy: {
      running: tinyproxyProcess !== null
    },
    ngrok: {
      running: ngrokUrl !== null,
      url: ngrokUrl ? ngrokUrl.replace('http://', '') : null
    },
    ready: isReady,
    message: isReady ? 'All services running' : 'Services starting...'
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/info', requireAuth, (req, res) => {
  if (!isReady) {
    return res.status(503).json({ error: 'Services not ready yet' });
  }

  const ngrokHost = ngrokUrl ? ngrokUrl.replace('http://', '').replace('https://', '') : null;
  const [host, port] = ngrokHost ? ngrokHost.split(':') : [null, '80'];

  res.json({
    proxy: {
      type: 'http',
      host: host,
      port: port || '80',
      user: 'toruser',
      pass: 'torpass123',
      full_url: ngrokUrl
    },
    tor: {
      socksPort: 9050,
      bootstrapProgress: torBootstrapProgress
    },
    tinyproxy: {
      port: 8888
    },
    usage: `curl -x ${host}:${port || '80'} -U toruser:torpass123 https://check.torproject.org`
  });
});

// Simple proxy endpoint for testing
app.all('/proxy', async (req, res) => {
  try {
    const targetUrl = req.query.url;
    if (!targetUrl) {
      return res.status(400).json({ error: 'Missing url parameter' });
    }

    const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
    const response = await axios.get(targetUrl, {
      httpAgent: agent,
      httpsAgent: agent,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }
    });

    res.json({
      status: response.status,
      data: response.data
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Cron job to keep service alive
cron.schedule('*/5 * * * *', async () => {
  if (!isReady) return;

  try {
    const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
    const randomHeaders = {
      'User-Agent': `Mozilla/5.0 (${Math.random() > 0.5 ? 'Windows NT 10.0' : 'Macintosh; Intel Mac OS X 10_15_7'})`,
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept': 'text/html,application/xhtml+xml'
    };

    await axios.get(`http://localhost:${PORT}/health`, {
      httpAgent: agent,
      httpsAgent: agent,
      headers: randomHeaders
    });

    console.log('✅ Keep-alive ping sent');
  } catch (error) {
    console.error('❌ Keep-alive ping failed:', error.message);
  }
});

// Initialize everything
async function initialize() {
  try {
    await startTor();
    startTinyproxy();
    await new Promise(resolve => setTimeout(resolve, 3000)); // Wait for tinyproxy
    await startNgrok();
    console.log('🎉 All services initialized successfully!');
  } catch (error) {
    console.error('❌ Initialization failed:', error);
    process.exit(1);
  }
}

// Start Express server
app.listen(PORT, () => {
  console.log(`🚀 Express server running on port ${PORT}`);
  initialize();
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down...');
  if (torProcess) torProcess.kill();
  if (tinyproxyProcess) tinyproxyProcess.kill();
  ngrok.disconnect();
  process.exit(0);
});
EOF

# Create directories
RUN mkdir -p /var/log/tor /var/lib/tor /var/log/tinyproxy

# Expose port
EXPOSE 3000

CMD ["node", "server.js"]
