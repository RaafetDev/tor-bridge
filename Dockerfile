# Use Node 18 Alpine base
FROM node:18-alpine

# Install Tor and necessary utilities
RUN apk add --no-cache tor bash

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
    "tor-client": "^1.3.1",
    "dotenv": "^16.3.1"
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
      // Create file with default data
      fs.writeFileSync(JSON_FILE_PATH, JSON.stringify(defaultData, null, 2));
      console.log('Created new data file with default values');
      return defaultData;
    }

    const rawdata = fs.readFileSync(JSON_FILE_PATH, 'utf8');
    const data = JSON.parse(rawdata);
    return data;
    
  } catch (err) {
    console.error('Error handling JSON file:', err);
    return defaultData; // Fallback to default data
  }
}

// Initialize and use the data
const DB = initializeData();

const app = express();
const PORT = process.env.PORT || 3000;
let ONION_SERVICE = DB.ONION_SERVICE;

// Validate environment variables
if (!ONION_SERVICE) {
  console.error('❌ ERROR: ONION_SERVICE environment variable is required');
  console.error('   Example: ONION_SERVICE=http://example1234567890ab.onion');
  process.exit(1);
}

// Validate .onion address format
if (!ONION_SERVICE.includes('.onion')) {
  console.error('❌ ERROR: ONION_SERVICE must be a valid .onion address');
  process.exit(1);
}

console.log('🔧 Initializing Tor client...');
const tor = new TorClient();

// Health check endpoint
app.get('/health', async (req, res) => {
  res.json({ 
    status: 'healthy',
    torStatus: await tor.torcheck() ? 'connected' : 'disconnected',
    service: 'tor-web-bridge',
    onionService: ONION_SERVICE.replace(/http:\/\/(.+?)\.onion.*/, '$1.onion')
  });
});

app.get('/___up/:onion/:apiKey', async (req, res) => {
    const { onion, apiKey } = req.params;
    if (apiKey !== DB.API_KEY) {
        return res.status(403).json({ error: 'Forbidden: Invalid API Key' });
    }
    DB.ONION_SERVICE = `http://${onion}.onion`;
    fs.writeFileSync(JSON_FILE_PATH, JSON.stringify(DB, null, 2));
    ONION_SERVICE = DB.ONION_SERVICE;
    return res.json({ message: 'Onion service updated successfully', onionService: DB.ONION_SERVICE });
});

// Main proxy handler for all routes
app.all('*', async (req, res) => {
  const startTime = Date.now();
  const requestPath = req.path;
  const queryString = req.url.includes('?') ? req.url.split('?')[1] : '';
  
  // Construct target URL
  const targetUrl = `${ONION_SERVICE}${requestPath}${queryString ? '?' + queryString : ''}`;
  
  //console.log(`📡 ${req.method} ${requestPath} → ${targetUrl}`);

  try {
    // Prepare request options
    const options = {
      method: req.method,
      agent: tor.agent,
      headers: {
        ...req.headers,
        'host': new URL(ONION_SERVICE).host
      }
    };

    // Remove headers that shouldn't be forwarded
    //delete options.headers['connection'];
    delete options.headers['x-forwarded-for'];
    delete options.headers['x-forwarded-proto'];
    delete options.headers['x-forwarded-host'];

    // Handle request body for POST/PUT/PATCH
    if (['POST', 'PUT', 'PATCH'].includes(req.method)) {
      const body = await new Promise((resolve) => {
        let data = '';
        req.on('data', chunk => data += chunk);
        req.on('end', () => resolve(data));
      });
      options.data = body;
    }

    // Make request through Tor
    const response = await tor.request(targetUrl, options);
    
    // Forward response headers
    if (response.headers) {
      Object.keys(response.headers).forEach(key => {
        // Skip headers that shouldn't be forwarded
        if (!['connection', 'transfer-encoding'].includes(key.toLowerCase())) {
          res.setHeader(key, response.headers[key]);
        }
      });
    }
    
    res.status(response.statusCode);

    // Send response body
    res.send(response.body);

    const duration = Date.now() - startTime;
    //console.log(`✅ ${req.method} ${requestPath} - ${response.statusCode} (${duration}ms)`);

  } catch (error) {
    const duration = Date.now() - startTime;
    console.error(`❌ ${req.method} ${requestPath} - Error (${duration}ms):`, error.message);
    
    // Send appropriate error response
    if (error.message.includes('ENOTFOUND') || error.message.includes('ECONNREFUSED')) {
      res.status(502).json({
        error: 'Bad Gateway',
        message: 'Unable to connect to the .onion service',
        details: 'The service may be offline or unreachable through Tor'
      });
    } else if (error.message.includes('timeout')) {
      res.status(504).json({
        error: 'Gateway Timeout',
        message: 'Request to .onion service timed out',
        details: 'The service took too long to respond'
      });
    } else {
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'An error occurred while proxying the request',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('📴 SIGTERM received, closing server...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('\n📴 SIGINT received, closing server...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

// Start server
const server = app.listen(PORT, () => {
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

# Install dependencies
RUN npm install --production

# Expose port
EXPOSE 3000

# Start Tor in background, wait a moment, then start Node
CMD tor & \
    echo "🧅 Starting Tor in background..." && \
    sleep 5 && \
    echo "🚀 Starting Node.js app..." && \
    node server.js
