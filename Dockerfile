# ╔══════════════════════════════════════════════════════════╗
# ║     SHΔDØW CORE V99 – BULLETPROOF DOCKERFILE (FIXED)     ║
# ║           npm install FIXED + socat FULL PROXY           ║
# ╚══════════════════════════════════════════════════════════╝

FROM node:20-alpine

# ──────────────────────────────────────────────────────────────
# 1. Clean install: apk + npm (NO CACHE, NO CONFLICTS)
# ──────────────────────────────────────────────────────────────
RUN apk add --no-cache tor socat torsocks curl && \
    npm install -g npm@latest && \
    npm config set fund false && \
    npm config set loglevel error && \
    mkdir -p /app && \
    cd /app && \
    echo '{"dependencies":{"express":"^4.19.2"}}' > package.json && \
    npm install --omit=dev --no-audit --no-fund && \
    rm -rf /root/.npm /var/cache/apk/*

WORKDIR /app

# ──────────────────────────────────────────────────────────────
# 2. torrc – Embedded
# ──────────────────────────────────────────────────────────────
RUN cat << 'EOF' > /app/torrc
SocksPort 9050
ControlPort 9051
Log notice stdout
DataDirectory /tmp/tor-data
AvoidDiskWrites 1
EOF

# ──────────────────────────────────────────────────────────────
# 3. ShadowTor Class
# ──────────────────────────────────────────────────────────────
RUN cat << 'EOF' > /app/shadow-tor.js
'use strict';
const { spawn } = require('child_process');
const EventEmitter = require('events');
const http = require('http');

class ShadowTor extends EventEmitter {
  constructor() {
    super();
    this.tor = null;
    this.socat = null;
    this.bootstrapStatus = 0;
    this.isReady = false;
    this.cronInterval = null;
    this.healthUrl = null;
    this.target = null;
    this.port = null;
  }

  start() {
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
      const req = http.get('http://check.torproject.org', {
        headers: { 'User-Agent': 'ShadowTor/99' },
        timeout: 8000
      }, res => {
        let data = '';
        res.on('data', c => data += c);
        res.on('end', () => {
          if (data.includes('Congratulations')) {
            this.isReady = true;
            this.emit('ready');
          } else if (attempts > 1) setTimeout(() => check(), 3000);
          else this.emit('error', new Error('Tor verification failed'));
        });
      });
      req.on('error', () => attempts > 1 ? setTimeout(() => check(), 3000) : this.emit('error', new Error('Tor unreachable')));
    };
    check();
  }

  socat(port, target) {
    if (!this.isReady) return this.emit('error', new Error('Tor not ready'));
    const [host, p] = target.split(':');
    this.port = port;
    this.target = target;
    this.socat = spawn('socat', [
      `TCP-LISTEN:${port},fork,reuseaddr,bind=0.0.0.0`,
      `SOCKS4A:127.0.0.1:${host}:${p || 80},socksport=9050`
    ], { stdio: 'ignore' });
    this.emit('log', `FULL PROXY ACTIVE: 0.0.0.0:${port} → ${target} [via Tor]`);
  }

  hiddenCron(minutes = 2) {
    if (this.cronInterval) clearInterval(this.cronInterval);
    const ms = minutes * 60 * 1000;
    this.healthUrl = `http://127.0.0.1:${this.port}/health`;
    this.cronInterval = setInterval(() => {
      if (!this.isReady || !this.healthUrl) return;
      spawn('torsocks', ['curl', '-s', '-m', '5', this.healthUrl], {
        stdio: 'ignore', detached: true
      }).unref();
    }, ms);
    this.emit('log', `Hidden cron: fake request every ${minutes} min via Tor`);
  }

  isRunning() { return this.tor && !this.tor.killed && this.isReady; }

  shutdown() {
    if (this.cronInterval) clearInterval(this.cronInterval);
    if (this.socat) this.socat.kill();
    if (this.tor) this.tor.kill();
    this.emit('log', 'ShadowTor shutdown complete');
  }
}

module.exports = ShadowTor;
EOF

# ──────────────────────────────────────────────────────────────
# 4. Main App – Express on 127.0.0.1, socat owns public port
# ──────────────────────────────────────────────────────────────
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
  shadow.socat(PORT, TARGET);
  shadow.hiddenCron(2);
});
shadow.on('error', err => console.error('[SHADOW] ERROR:', err.message));
shadow.on('exit', code => console.log(`[SHADOW] Tor exited (${code})`));
shadow.on('log', line => console.log(`[tor] ${line}`));

shadow.start();

// Express: ONLY /health → 127.0.0.1
app.get('/health', (req, res) => {
  res.json({
    status: 'SHADOW ACTIVE',
    tor: {
      running: shadow.isRunning(),
      bootstrap: `${shadow.bootstrapStatus}%`
    },
    proxy: `ALL PATHS → ${TARGET} [via socat]`,
    timestamp: new Date().toISOString(),
    note: 'All other paths are proxied directly to .onion'
  }, null, 2);
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Express health server on 127.0.0.1:${PORT}`);
  console.log(`socat owns 0.0.0.0:${PORT} → ${TARGET}`);
});

process.on('SIGTERM', () => {
  shadow.shutdown();
  process.exit(0);
});
EOF

EXPOSE $PORT

CMD ["node", "index.js"]
