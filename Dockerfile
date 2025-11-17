FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    tor \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Create package.json
RUN cat <<'EOF' > package.json
{
  "name": "render-tor-tunnel",
  "version": "1.0.0",
  "description": "Render.com app with Tor and Pinggy.io tunneling",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.6.1",
    "ssh2": "^1.14.0",
    "axios": "^1.6.2",
    "socks-proxy-agent": "^8.0.2",
    "node-cron": "^3.0.3"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

# Install dependencies
RUN npm install --production

# Create data.json
RUN cat <<'EOF' > data.json
{
  "config": {
    "appName": "Render Tor Tunnel",
    "version": "1.0.0"
  },
  "pinggyHost": null,
  "pinggyPort": null,
  "lastUpdate": null
}
EOF

# Create server.js
RUN cat <<'EOF' > server.js
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { Client: SSHClient } = require('ssh2');
const net = require('net');
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');
const cron = require('node-cron');

// Configuration
const PORT = process.env.PORT || 3000;
const TCP_LISTENER_PORT = 8000;
const SSH_TARGET_PORT = 22;
const ADMIN_PIN = process.env.ADMIN_PIN || '1234';
const AFRAID_API_KEY = process.env.AFRAID_API_KEY || '';
const AFRAID_SUBDOMAIN = process.env.AFRAID_SUBDOMAIN || '';

// Data file
const DATA_FILE = './data.json';

// Global state
let torProcess = null;
let torReady = false;
let pinggySSH = null;
let pinggyTCPHost = null;
let pinggyTCPPort = null;
let tcpServer = null;
const logs = [];
const MAX_LOGS = 1000;

// Load/Save data
function loadData() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    }
  } catch (error) {
    logEvent('error', `Failed to load data: ${error.message}`);
  }
  return { config: {}, lastUpdate: null };
}

function saveData(data) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
  } catch (error) {
    logEvent('error', `Failed to save data: ${error.message}`);
  }
}

// Logging
function logEvent(level, message) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message
  };
  logs.push(entry);
  if (logs.length > MAX_LOGS) logs.shift();
  console.log(`[${level.toUpperCase()}] ${message}`);
  
  // Emit to connected socket.io clients
  if (io) {
    io.emit('log', entry);
  }
}

// Tor Helper
async function startTor() {
  return new Promise((resolve, reject) => {
    logEvent('info', 'Starting Tor...');
    
    torProcess = spawn('tor', ['--SocksPort', '9050']);
    
    let bootstrapProgress = 0;
    
    torProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log('Tor:', output);
      
      // Check for bootstrap progress
      const match = output.match(/Bootstrapped (\d+)%/);
      if (match) {
        bootstrapProgress = parseInt(match[1]);
        logEvent('info', `Tor bootstrap: ${bootstrapProgress}%`);
        
        if (bootstrapProgress === 100) {
          torReady = true;
          logEvent('info', 'Tor is fully bootstrapped and ready');
          resolve();
        }
      }
    });
    
    torProcess.stderr.on('data', (data) => {
      console.error('Tor error:', data.toString());
    });
    
    torProcess.on('close', (code) => {
      logEvent('error', `Tor process exited with code ${code}`);
      torReady = false;
      if (bootstrapProgress < 100) {
        reject(new Error('Tor failed to bootstrap'));
      }
    });
    
    // Timeout after 60 seconds
    setTimeout(() => {
      if (!torReady) {
        reject(new Error('Tor bootstrap timeout'));
      }
    }, 60000);
  });
}

// TCP Listener that relays to SSH over Tor
function startTCPListener() {
  tcpServer = net.createServer((socket) => {
    logEvent('info', `TCP connection received from ${socket.remoteAddress}`);
    
    // Create SSH connection over Tor
    const sshConn = net.createConnection({
      host: '127.0.0.1', // localhost SSH
      port: SSH_TARGET_PORT
    });
    
    socket.pipe(sshConn);
    sshConn.pipe(socket);
    
    socket.on('error', (err) => {
      logEvent('error', `TCP socket error: ${err.message}`);
    });
    
    sshConn.on('error', (err) => {
      logEvent('error', `SSH connection error: ${err.message}`);
    });
    
    socket.on('close', () => {
      sshConn.end();
    });
    
    sshConn.on('close', () => {
      socket.end();
    });
  });
  
  tcpServer.listen(TCP_LISTENER_PORT, () => {
    logEvent('info', `TCP listener started on port ${TCP_LISTENER_PORT}`);
  });
}

// Pinggy.io SSH tunnel
function startPinggyTunnel() {
  return new Promise((resolve, reject) => {
    logEvent('info', 'Starting Pinggy.io tunnel...');
    
    const conn = new SSHClient();
    pinggySSH = conn;
    
    conn.on('ready', () => {
      logEvent('info', 'Pinggy.io SSH connection established');
      
      conn.forwardOut(
        '0.0.0.0',
        0,
        'localhost',
        TCP_LISTENER_PORT,
        (err, stream) => {
          if (err) {
            logEvent('error', `Pinggy.io forward error: ${err.message}`);
            reject(err);
            return;
          }
          logEvent('info', 'Pinggy.io port forwarding active');
        }
      );
    });
    
    conn.on('tcp connection', (info, accept, reject) => {
      logEvent('info', `Pinggy.io TCP connection: ${info.srcIP}:${info.srcPort}`);
      const stream = accept();
      
      const localConn = net.createConnection({
        host: 'localhost',
        port: TCP_LISTENER_PORT
      });
      
      stream.pipe(localConn);
      localConn.pipe(stream);
      
      stream.on('error', (err) => {
        logEvent('error', `Pinggy stream error: ${err.message}`);
      });
      
      localConn.on('error', (err) => {
        logEvent('error', `Local connection error: ${err.message}`);
      });
    });
    
    let outputBuffer = '';
    
    conn.on('banner', (message) => {
      outputBuffer += message;
      console.log('Pinggy banner:', message);
      
      // Extract TCP URL
      const tcpMatch = message.match(/tcp:\/\/([^:]+):(\d+)/);
      if (tcpMatch) {
        pinggyTCPHost = tcpMatch[1];
        pinggyTCPPort = tcpMatch[2];
        logEvent('info', `Pinggy TCP endpoint: ${pinggyTCPHost}:${pinggyTCPPort}`);
        
        // Update data
        const data = loadData();
        data.pinggyHost = pinggyTCPHost;
        data.pinggyPort = pinggyTCPPort;
        data.lastUpdate = new Date().toISOString();
        saveData(data);
        
        // Update Afraid.org DNS
        updateAfraidDNS().then(() => {
          resolve();
        }).catch((err) => {
          logEvent('error', `Failed to update Afraid.org: ${err.message}`);
          resolve(); // Don't reject, tunnel is still working
        });
      }
    });
    
    conn.on('error', (err) => {
      logEvent('error', `Pinggy.io SSH error: ${err.message}`);
      reject(err);
    });
    
    conn.on('close', () => {
      logEvent('info', 'Pinggy.io SSH connection closed');
      pinggySSH = null;
    });
    
    // Connect to Pinggy.io
    conn.connect({
      host: 'free.pinggy.io',
      port: 443,
      username: 'VPx6tIf3RXE+tcp',
      tryKeyboard: true,
      keepaliveInterval: 30000,
      readyTimeout: 30000
    });
    
    // Timeout
    setTimeout(() => {
      if (!pinggyTCPHost) {
        reject(new Error('Pinggy.io tunnel timeout'));
      }
    }, 30000);
  });
}

// Update Afraid.org DNS
async function updateAfraidDNS() {
  if (!AFRAID_API_KEY || !AFRAID_SUBDOMAIN || !pinggyTCPHost) {
    logEvent('warn', 'Afraid.org update skipped: missing config');
    return;
  }
  
  try {
    logEvent('info', `Updating Afraid.org subdomain ${AFRAID_SUBDOMAIN} to ${pinggyTCPHost}`);
    
    // Afraid.org API format: https://freedns.afraid.org/api/?action=getdyndns&sha=API_KEY
    // Then update using: https://freedns.afraid.org/dynamic/update.php?UPDATE_HASH
    
    // First, get the update hash
    const listResponse = await axios.get(
      `https://freedns.afraid.org/api/?action=getdyndns&sha=${AFRAID_API_KEY}`
    );
    
    const lines = listResponse.data.split('\n');
    let updateUrl = null;
    
    for (const line of lines) {
      if (line.includes(AFRAID_SUBDOMAIN)) {
        const parts = line.split('|');
        if (parts.length > 0) {
          updateUrl = parts[0];
          break;
        }
      }
    }
    
    if (updateUrl) {
      // Update with CNAME
      const updateResponse = await axios.get(updateUrl.replace(/\?.*/, `?${pinggyTCPHost}`));
      logEvent('info', `Afraid.org DNS updated: ${updateResponse.data}`);
    } else {
      logEvent('error', 'Failed to find Afraid.org update URL');
    }
  } catch (error) {
    logEvent('error', `Afraid.org update error: ${error.message}`);
    throw error;
  }
}

// Refresh Pinggy.io tunnel
async function refreshPinggyTunnel() {
  logEvent('info', 'Refreshing Pinggy.io tunnel...');
  
  if (pinggySSH) {
    pinggySSH.end();
    pinggySSH = null;
  }
  
  try {
    await startPinggyTunnel();
    logEvent('info', 'Pinggy.io tunnel refreshed successfully');
  } catch (error) {
    logEvent('error', `Failed to refresh Pinggy.io tunnel: ${error.message}`);
  }
}

// Keep-alive ping with Tor proxy
async function keepAlivePing() {
  if (!torReady) {
    logEvent('warn', 'Tor not ready, skipping keep-alive ping');
    return;
  }
  
  try {
    const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
    
    const userAgents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
    ];
    
    const response = await axios.get(`http://localhost:${PORT}/health`, {
      httpAgent: agent,
      httpsAgent: agent,
      headers: {
        'User-Agent': userAgents[Math.floor(Math.random() * userAgents.length)]
      },
      timeout: 10000
    });
    
    logEvent('info', `Keep-alive ping successful: ${response.status}`);
  } catch (error) {
    logEvent('error', `Keep-alive ping failed: ${error.message}`);
  }
}

// Express app
const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(express.json());

// Middleware to check admin PIN
function requireAdmin(req, res, next) {
  const pin = req.headers['x-admin-pin'] || req.query.pin;
  if (pin !== ADMIN_PIN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// Routes
app.get('/', (req, res) => {
  res.json({ status: 'up' });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    torReady,
    pinggyHost: pinggyTCPHost,
    pinggyPort: pinggyTCPPort
  });
});

app.get('/api/status', requireAdmin, (req, res) => {
  res.json({
    torReady,
    pinggyHost: pinggyTCPHost,
    pinggyPort: pinggyTCPPort,
    data: loadData()
  });
});

app.post('/api/config', requireAdmin, (req, res) => {
  const data = loadData();
  data.config = { ...data.config, ...req.body };
  saveData(data);
  logEvent('info', 'Configuration updated');
  res.json({ success: true, data });
});

app.get('/api/logs', requireAdmin, (req, res) => {
  res.json({ logs });
});

app.post('/api/refresh-tunnel', requireAdmin, async (req, res) => {
  res.json({ success: true, message: 'Tunnel refresh initiated' });
  refreshPinggyTunnel();
});

// Socket.io for real-time updates
io.use((socket, next) => {
  const pin = socket.handshake.auth.pin;
  if (pin !== ADMIN_PIN) {
    return next(new Error('Unauthorized'));
  }
  next();
});

io.on('connection', (socket) => {
  logEvent('info', 'Admin client connected via Socket.io');
  
  // Send current logs
  socket.emit('logs', logs);
  
  socket.on('disconnect', () => {
    logEvent('info', 'Admin client disconnected');
  });
});

// Cron jobs
cron.schedule('*/10 * * * *', () => {
  logEvent('info', 'Running scheduled Pinggy.io tunnel refresh');
  refreshPinggyTunnel();
});

cron.schedule('*/5 * * * *', () => {
  logEvent('info', 'Running keep-alive ping');
  keepAlivePing();
});

// Initialize
async function initialize() {
  try {
    logEvent('info', 'Starting initialization...');
    
    // Start Tor
    await startTor();
    
    // Start TCP listener
    startTCPListener();
    
    // Start Pinggy.io tunnel
    await startPinggyTunnel();
    
    logEvent('info', 'Initialization complete');
  } catch (error) {
    logEvent('error', `Initialization failed: ${error.message}`);
    process.exit(1);
  }
}

// Start Express server
server.listen(PORT, () => {
  logEvent('info', `Express server listening on port ${PORT}`);
  initialize();
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logEvent('info', 'SIGTERM received, shutting down gracefully');
  
  if (pinggySSH) pinggySSH.end();
  if (torProcess) torProcess.kill();
  if (tcpServer) tcpServer.close();
  
  server.close(() => {
    logEvent('info', 'Server closed');
    process.exit(0);
  });
});
EOF

# Expose port
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
