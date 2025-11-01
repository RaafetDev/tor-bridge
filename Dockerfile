# ╔══════════════════════════════════════════════════════════╗
# ║   SHΔDØW CORE V99 – PORT-BOUND PROXY (RENDER-PROOF)      ║
# ║     IMMEDIATE BIND + torsocks FORWARDER — NO SOCAT       ║
# ╚══════════════════════════════════════════════════════════╝

FROM node:20-alpine

# Clean install: apk + npm
RUN apk add --no-cache tor torsocks curl && \
    npm install -g npm@latest && \
    npm config set fund false && \
    npm config set loglevel error && \
    mkdir -p /app && \
    cd /app && \
    echo '{"dependencies":{"express":"^4.19.2"}}' > package.json && \
    npm install --omit=dev --no-audit --no-fund && \
    rm -rf /root/.npm /var/cache/apk/*

WORKDIR /app

# torrc
RUN cat << 'EOF' > /app/torrc
SocksPort 9050
ControlPort 9051
Log notice stdout
DataDirectory /tmp/tor-data
AvoidDiskWrites 1
EOF

# ShadowTor Class (simplified for torsocks forwarding)
RUN cat << 'EOF' > /app/shadow-tor.js
'use strict';
const { spawn } = require('child_process');
const EventEmitter = require('events');
const http = require('http');
const https = require('https');
const { exec } = require('child_process');

class ShadowTor extends EventEmitter {
  constructor() {
    super();
    this.tor = null;
    this.bootstrapStatus = 0;
    this.isReady = false;
    this.target = null;
  }

  start(target) {
    this.target = target;
    this.tor = spawn('tor', ['-f', '/app/torrc'], { stdio: ['ignore', 'pipe', 'pipe'] });
    this.tor.stdout.on('data', d => this.parseLog(d.toString()));
    this.tor.stderr.on('data', d => this.parseLog(d.toString()));
    this.tor.on('close', code => this.emit('exit', code));
    this.tor.on('error', err => this.emit('error', err));
    this.emit('log', 'Tor process spawned');
  }

  parseLog(log) {
    log.split('\n').forEach(line => {
      const m = line.match(/Bootstrapped (\d+)%/);
      if (m && parseInt(m[1]) > this.bootstrapStatus) {
        this.bootstrapStatus = parseInt(m[1]);
        this.emit('bootstrap', this.bootstrapStatus);
        if (this.bootstrapStatus === 100) this.verifyConnection();
      }
      if (line.trim()) this.emit('log', line.trim());
    });
  }

  verifyConnection(attempts = 5) {
    const check = () => {
      exec('torsocks curl -s -m 5 http://check.torproject.org', (err, stdout) => {
        if (!err && stdout.includes('Congratulations')) {
          this.isReady = true;
          this.emit('ready');
        } else if (attempts > 1) setTimeout(() => check(), 3000);
        else this.emit('error', new Error('Tor verification failed'));
      });
    };
    check();
  }

  // Forward request via torsocks curl
  forward(req, res, callback) {
    if (!this.isReady) return callback(new Error('Tor not ready'));
    const url = `http://${this.target}${req.url}`;
    exec(`torsocks curl -s -m 10 -H "Host: ${this.target.split(':')[0]}" "${url}"`, (err, stdout, stderr) => {
      if (err) return callback(err);
      res.set('Content-Type', 'text/html; charset=utf-8'); // Adjust as needed
      res.send(stdout);
    });
  }

  isRunning() { return this.tor && !this.tor.killed && this.isReady; }

  shutdown() {
    if (this.tor) this.tor.kill();
    this.emit('log', 'ShadowTor shutdown complete');
  }
}

module.exports = ShadowTor;
EOF

# Main App: Express binds IMMEDIATELY to 0.0.0.0, forwards via torsocks
RUN cat << 'EOF' > /app/index.js
const express = require('express');
const ShadowTor = require('./shadow-tor.js');

const app = express();
const PORT = process.env.PORT || 8080;
const TARGET = process.env.TARGET || 'youroniondomain.onion:80';

const shadow = new ShadowTor();

shadow.on('bootstrap', p => console.log(`[SHADOW] Bootstrapped ${p}%`));
shadow.on('ready', () => {
  console.log('[SHADOW] Tor READY & VERIFIED');
  shadow.hiddenCron?.(2); // Optional cron
});
shadow.on('error', err => console.error('[SHADOW] ERROR:', err.message));
shadow.on('exit', code => console.log(`[SHADOW] Tor exited (${code})`));
shadow.on('log', line => console.log(`[tor] ${line}`));

shadow.start(TARGET);

// Health endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'SHADOW ACTIVE',
    tor: {
      running: shadow.isRunning(),
      bootstrap: `${shadow.bootstrapStatus}%`
    },
    proxy: `ALL PATHS → ${TARGET} [via torsocks]`,
    timestamp: new Date().toISOString(),
    note: 'Proxy ready; traffic forwarded over Tor'
  }, null, 2);
});

// Catch-all: Forward ALL other paths to onion via torsocks
app.use((req, res) => {
  if (shadow.isReady) {
    shadow.forward(req, res, (err) => {
      if (err) {
        res.status(502).send(`Tor Proxy Error: ${err.message}`);
      }
    });
  } else {
    res.status(503).send('Shadow Proxy Booting... Tor circuits forming.');
  }
});

// BIND IMMEDIATELY to 0.0.0.0:$PORT
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[SHADOW] Express bound to 0.0.0.0:${PORT} — Render scanner satisfied`);
  console.log(`[SHADOW] Proxying ALL paths to ${TARGET} via Tor`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  shadow.shutdown();
  process.exit(0);
});
EOF

EXPOSE $PORT

CMD ["node", "index.js"]
