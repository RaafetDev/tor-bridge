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
    "@ngrok/ngrok": "^1.4.0"
  }
}
EOF

# Install dependencies
RUN npm install

# Create Tor configuration
RUN cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
DataDirectory /tmp/tor
Log notice stdout
EOF

# Create Tinyproxy configuration (log to stdout)
RUN cat > /etc/tinyproxy/tinyproxy.conf << 'EOF'
User nobody
Group nogroup
Port 8888
Timeout 600
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
const ngrok = require('@ngrok/ngrok');
const fs = require('fs');
const http = require('http');
const net = require('net');

const app = express();
const PORT = process.env.PORT || 3000;
const PROXY_PORT = 8889; // Secondary port for CONNECT proxy
const LOGIN_TOKEN = process.env.LOGIN_TOKEN || 'gogo';
const NGROK_AUTHTOKEN = '2qS36Q7lJ86l0oxrkURnKGnT2Hb_3MmsHAsxmRaf8RW7u5rA2';
const NGROK_DOMAIN = 'wade-unwrung-abrasively.ngrok-free.dev';

let torProcess = null;
let tinyproxyProcess = null;
let ngrokUrl = null;
let ngrokListener = null;
let torBootstrapProgress = 0;
let isReady = false;
let proxyServer = null;

// Start HTTP CONNECT Proxy Server (bypass ngrok browser warning)
function startProxyServer() {
  proxyServer = http.createServer();
  
  // Handle CONNECT method for HTTPS tunneling
  proxyServer.on('connect', (req, clientSocket, head) => {
    console.log(`CONNECT request to: ${req.url}`);
    
    // Connect to tinyproxy
    const serverSocket = net.connect(8888, 'localhost', () => {
      clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      serverSocket.write(head);
      serverSocket.pipe(clientSocket);
      clientSocket.pipe(serverSocket);
    });

    serverSocket.on('error', (err) => {
      console.error('Server socket error:', err);
      clientSocket.end();
    });

    clientSocket.on('error', (err) => {
      console.error('Client socket error:', err);
      serverSocket.end();
    });
  });

  // Handle regular HTTP requests
  proxyServer.on('request', (req, res) => {
    console.log(`HTTP request to: ${req.url}`);
    
    const options = {
      hostname: 'localhost',
      port: 8888,
      path: req.url,
      method: req.method,
      headers: req.headers
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', (err) => {
      console.error('Proxy request error:', err);
      res.writeHead(500);
      res.end();
    });

    req.pipe(proxyReq);
  });

  proxyServer.listen(PROXY_PORT, () => {
    console.log(`🔌 HTTP CONNECT Proxy listening on port ${PROXY_PORT}`);
  });
}

// Start Tor
function startTor() {
  return new Promise((resolve, reject) => {
    console.log('🧅 Starting Tor...');
    
    // Create tor data directory with proper permissions
    if (!fs.existsSync('/tmp/tor')) {
      fs.mkdirSync('/tmp/tor', { recursive: true, mode: 0o700 });
    }
    
    torProcess = spawn('tor', ['-f', '/etc/tor/torrc']);

    torProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`[Tor] ${output.trim()}`);

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
      console.error(`[Tor Error] ${data.toString().trim()}`);
    });

    torProcess.on('close', (code) => {
      console.log(`Tor process exited with code ${code}`);
      if (code !== 0 && torBootstrapProgress < 100) {
        reject(new Error('Tor failed to start'));
      }
    });

    // Timeout after 60 seconds
    setTimeout(() => {
      if (torBootstrapProgress < 100) {
        reject(new Error('Tor bootstrap timeout'));
      }
    }, 60000);
  });
}

// Start Tinyproxy
function startTinyproxy() {
  return new Promise((resolve, reject) => {
    console.log('🔧 Starting Tinyproxy...');
    
    tinyproxyProcess = spawn('tinyproxy', ['-d', '-c', '/etc/tinyproxy/tinyproxy.conf']);

    let started = false;

    tinyproxyProcess.stdout.on('data', (data) => {
      const output = data.toString().trim();
      console.log(`[Tinyproxy] ${output}`);
      if (output.includes('Listening on') || output.includes('Creating new child')) {
        if (!started) {
          started = true;
          resolve();
        }
      }
    });

    tinyproxyProcess.stderr.on('data', (data) => {
      const output = data.toString().trim();
      if (!output.includes('Permission denied')) {
        console.log(`[Tinyproxy] ${output}`);
      }
    });

    tinyproxyProcess.on('close', (code) => {
      console.log(`Tinyproxy process exited with code ${code}`);
    });

    // Resolve after 2 seconds if no explicit confirmation
    setTimeout(() => {
      if (!started) {
        console.log('⚠️  Tinyproxy might be running (no confirmation message)');
        resolve();
      }
    }, 2000);
  });
}

// Start Ngrok
async function startNgrok() {
  console.log('🌐 Starting Ngrok tunnel...');
  
  if (!NGROK_AUTHTOKEN) {
    console.error('❌ NGROK_AUTHTOKEN environment variable is required!');
    console.error('Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken');
    return;
  }

  try {
    // Configure ngrok with authtoken
    const ngrokConfig = {
      addr: PROXY_PORT, // Point to our CONNECT proxy wrapper
      authtoken: NGROK_AUTHTOKEN,
      schemes: ['http']  // Force HTTP only (no HTTPS)
    };

    // Use static domain if provided
    if (NGROK_DOMAIN) {
      ngrokConfig.domain = NGROK_DOMAIN;
      console.log(`🎯 Using static domain: ${NGROK_DOMAIN}`);
    } else {
      console.log('⚠️  No NGROK_DOMAIN set, using random domain');
    }

    // Connect ngrok
    ngrokListener = await ngrok.forward(ngrokConfig);
    const rawUrl = ngrokListener.url();
    ngrokUrl = rawUrl.replace('https://', 'http://');
    
    console.log(`✅ Ngrok tunnel established: ${ngrokUrl}`);
    isReady = true;
  } catch (error) {
    console.error('❌ Failed to start Ngrok:', error.message);
    console.error('Full error:', error);
    
    // Common error messages
    if (error.message.includes('authentication')) {
      console.error('⚠️  Check your NGROK_AUTHTOKEN - it might be invalid');
    }
    if (error.message.includes('domain')) {
      console.error('⚠️  Check your NGROK_DOMAIN - it might be invalid or not claimed');
    }
  }
}

// Middleware for authentication
function requireAuth(req, res, next) {
  const token = req.headers['authorization'] || req.headers['login'];
  if (token === LOGIN_TOKEN) {
    next();
  } else {
    res.status(401).json({ error: 'Unauthorized - Missing or invalid login header' });
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
      configured: !!NGROK_AUTHTOKEN,
      staticDomain: NGROK_DOMAIN || 'random',
      url: ngrokUrl ? ngrokUrl.replace('http://', '').replace('https://', '') : null
    },
    ready: isReady,
    message: isReady ? '✅ All services running' : '⏳ Services starting...'
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

  const cleanUrl = ngrokUrl ? ngrokUrl.replace('http://', '').replace('https://', '') : null;
  const [host, port] = cleanUrl ? cleanUrl.split(':') : [null, '80'];

  res.json({
    proxy: {
      type: 'http',
      host: host,
      port: port || '80',
      user: 'toruser',
      pass: 'torpass123',
      full_url: ngrokUrl,
      curl_example: `curl -x http://toruser:torpass123@${host}:${port || '80'} https://check.torproject.org`,
      wget_example: `wget -e use_proxy=yes -e http_proxy=${host}:${port || '80'} --proxy-user=toruser --proxy-password=torpass123 -O- https://check.torproject.org`
    },
    tor: {
      socksPort: 9050,
      bootstrapProgress: torBootstrapProgress
    },
    tinyproxy: {
      port: 8888
    },
    ngrok: {
      domain: NGROK_DOMAIN || 'random',
      authtoken_set: !!NGROK_AUTHTOKEN
    }
  });
});

// Simple proxy endpoint for testing
app.all('/proxy', async (req, res) => {
  try {
    const targetUrl = req.query.url;
    if (!targetUrl) {
      return res.status(400).json({ error: 'Missing url parameter. Usage: /proxy?url=https://example.com' });
    }

    const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
    const response = await axios.get(targetUrl, {
      httpAgent: agent,
      httpsAgent: agent,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      },
      timeout: 30000
    });

    res.json({
      status: response.status,
      url: targetUrl,
      via_tor: true,
      preview: response.data.toString().substring(0, 500) + '...'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Cron job to keep service alive (every 5 minutes)
cron.schedule('*/5 * * * *', async () => {
  if (!isReady) return;

  try {
    const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
    const randomHeaders = {
      'User-Agent': `Mozilla/5.0 (${Math.random() > 0.5 ? 'Windows NT 10.0; Win64; x64' : 'Macintosh; Intel Mac OS X 10_15_7'}) AppleWebKit/537.36`,
      'Accept-Language': `en-US,en;q=0.${Math.floor(Math.random() * 10)}`,
      'Accept': 'text/html,application/xhtml+xml'
    };

    await axios.get(`http://localhost:${PORT}/health`, {
      httpAgent: agent,
      httpsAgent: agent,
      headers: randomHeaders,
      timeout: 10000
    });

    console.log('✅ Keep-alive ping sent at', new Date().toISOString());
  } catch (error) {
    console.error('❌ Keep-alive ping failed:', error.message);
  }
});

// Initialize everything
async function initialize() {
  try {
    console.log('🚀 Initializing services...');
    
    if (!NGROK_AUTHTOKEN) {
      console.error('⚠️  CRITICAL: NGROK_AUTHTOKEN not set!');
      console.error('Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken');
      console.error('Set it in Render: Dashboard > Service > Environment');
    }
    
    // Start Tor and wait for 100%
    await startTor();
    
    // Start Tinyproxy
    await startTinyproxy();
    
    // Wait a bit for tinyproxy to be ready
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Start CONNECT proxy wrapper
    startProxyServer();
    
    // Wait for proxy server
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Start Ngrok
    await startNgrok();
    
    if (isReady) {
      console.log('🎉 All services initialized successfully!');
      console.log(`📡 Proxy available at: ${ngrokUrl}`);
      console.log(`👤 Username: toruser`);
      console.log(`🔑 Password: torpass123`);
    } else {
      console.error('⚠️  Services started but ngrok failed');
    }
  } catch (error) {
    console.error('❌ Initialization failed:', error.message);
    process.exit(1);
  }
}

// Start Express server
app.listen(PORT, () => {
  console.log(`🚀 Express server running on port ${PORT}`);
  console.log(`📝 Environment check:`);
  console.log(`   - NGROK_AUTHTOKEN: ${NGROK_AUTHTOKEN ? '✅ Set' : '❌ Missing'}`);
  console.log(`   - NGROK_DOMAIN: ${NGROK_DOMAIN || '⚠️  Not set (random domain)'}`);
  console.log(`   - LOGIN_TOKEN: ${LOGIN_TOKEN ? '✅ Set' : '❌ Missing'}`);
  initialize();
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('🛑 Shutting down...');
  if (torProcess) torProcess.kill();
  if (tinyproxyProcess) tinyproxyProcess.kill();
  if (proxyServer) proxyServer.close();
  if (ngrokListener) await ngrokListener.close();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('🛑 Shutting down...');
  if (torProcess) torProcess.kill();
  if (tinyproxyProcess) tinyproxyProcess.kill();
  if (proxyServer) proxyServer.close();
  if (ngrokListener) await ngrokListener.close();
  process.exit(0);
});
EOF

# Create directories with proper permissions
RUN mkdir -p /tmp/tor && chmod 700 /tmp/tor

# Expose port
EXPOSE 3000

CMD ["node", "server.js"]
