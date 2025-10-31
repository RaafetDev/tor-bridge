# Use Node 18 Alpine base
FROM node:18-alpine

# Install Tor and necessary utilities
RUN apk add --no-cache tor bash git python3 make g++

# Create app directory
WORKDIR /usr/src/app

# Create package.json
RUN cat > package.json << 'EOF'
{
  "name": "tor-web-bridge",
  "version": "1.0.0",
  "description": "Private Tor to Web bridge for accessing .onion services",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "keywords": ["tor", "bridge", "onion", "proxy"],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2",
    "dotenv": "^16.3.1",
    "tor-client": "github:michaldziuba03/tor-client"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

# Create server.js
RUN cat > server.js << 'EOF'
const express = require('express');
const { TorClient } = require('tor-client');
const fs = require('fs');
const path = require('path');

const JSON_FILE_PATH = './data.json';
const defaultData = {
  ONION_SERVICE: '6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion',
  API_KEY: 'relive'
};

function initializeData() {
  try {
    if (!fs.existsSync(JSON_FILE_PATH)) {
      fs.writeFileSync(JSON_FILE_PATH, JSON.stringify(defaultData, null, 2));
      console.log('Created new data file with default values');
      return defaultData;
    }
    const rawdata = fs.readFileSync(JSON_FILE_PATH, 'utf8');
    return JSON.parse(rawdata);
  } catch (err) {
    console.error('Error handling JSON file:', err);
    return defaultData;
  }
}

const DB = initializeData();
const app = express();
const PORT = process.env.PORT || 3000;
let ONION_SERVICE = DB.ONION_SERVICE;

if (!ONION_SERVICE) {
  console.error('❌ ERROR: Missing ONION_SERVICE value');
  process.exit(1);
}
if (!ONION_SERVICE.includes('.onion')) {
  console.error('❌ ERROR: Invalid .onion address');
  process.exit(1);
}

console.log('🔧 Initializing Tor client...');
const tor = new TorClient();

app.get('/health', async (req, res) => {
  try {
    const connected = await tor.torcheck();
    res.json({
      status: 'healthy',
      torStatus: connected ? 'connected' : 'disconnected',
      onionService: ONION_SERVICE
    });
  } catch (e) {
    res.json({ status: 'unhealthy', error: e.message });
  }
});

app.all('*', async (req, res) => {
  try {
    const url = `${ONION_SERVICE}${req.originalUrl}`;
    const response = await tor.request(url);
    res.status(response.statusCode).send(response.body);
  } catch (e) {
    console.error('Proxy error:', e.message);
    res.status(502).json({ error: 'Bad Gateway', message: e.message });
  }
});

app.listen(PORT, () => {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🚀 Tor Web Bridge Running');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`📍 Server:        http://localhost:${PORT}`);
  console.log(`🧅 Onion Service: ${ONION_SERVICE}`);
  console.log(`💚 Health Check:  http://localhost:${PORT}/health`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
});
EOF

# Add .env placeholder
RUN cat > .env << 'EOF'
PORT=3000
NODE_ENV=production
EOF

# Add .dockerignore
RUN cat > .dockerignore << 'EOF'
node_modules
npm-debug.log
.env
.git
.gitignore
README.md
.dockerignore
EOF

# Install dependencies, including tor-client from GitHub
RUN npm install

# Expose port
EXPOSE 3000

# Start Tor in background, wait a moment, then start Node
CMD tor & \
    echo "🧅 Starting Tor in background..." && \
    sleep 30 && \
    echo "🚀 Starting Node.js app..." && \
    node server.js
