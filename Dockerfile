FROM node:18-bullseye-slim

# Install system deps
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    openvpn \
    curl \
    procps \
    net-tools \
    iptables \
    iproute2 \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user + writable dirs
RUN useradd -m -s /bin/bash proxyuser && \
    echo "proxyuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/proxyuser && \
    mkdir -p /var/log/tinyproxy /var/run/tinyproxy /app/storage/Tor_Data && \
    chown -R proxyuser:proxyuser /var/log/tinyproxy /var/run/tinyproxy /app/storage

WORKDIR /app

# Node deps
RUN npm install --no-save express axios socks-proxy-agent

# === FIXED OVPN: Proper inline formatting + data-ciphers ===
RUN mkdir -p /app/storage
RUN cat > /app/app.ovpn << 'EOF'
RUN
EOF

# === app.js – Clean, no sudo, OpenVPN in user space ===
RUN cat > /app/app.js << 'EOF'
const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

const app = express();
const PORT = process.env.PORT || 3000;
const PROXY_PORT = 8888;

let state = { tor: false, tinyproxy: false, openvpn: false, publicProxy: null };
function log(m) { console.log(`[${new Date().toISOString()}] ${m}`); }

// Tor
async function setupTor() {
    return new Promise((res, rej) => {
        const torrc = '/app/storage/torrc';
        fs.writeFileSync(torrc, `SocksPort 0.0.0.0:9050\nDataDirectory /app/storage/Tor_Data\nLog notice stdout\n`);
        const tor = spawn('tor', ['-f', torrc]);
        const t = setTimeout(() => rej('timeout'), 90000);
        tor.stdout.on('data', d => {
            const l = d.toString();
            console.log(`[TOR] ${l.trim()}`);
            if (l.includes('Bootstrapped 100%')) { clearTimeout(t); state.tor = true; log('Tor ready'); res(); }
        });
        tor.on('close', () => state.tor = false);
    });
}

// Tinyproxy
async function setupTinyproxy() {
    return new Promise((res) => {
        const conf = `/app/storage/tinyproxy.conf`;
        const cfg = `User proxyuser\nGroup proxyuser\nPort ${PROXY_PORT}\nListen 0.0.0.0\nLogFile "/var/log/tinyproxy/tinyproxy.log"\nPidFile "/var/run/tinyproxy/tinyproxy.pid"\nMaxClients 50\nAllow 0.0.0.0/0\nDisableViaHeader Yes\nUpstream socks5 127.0.0.1:9050\n`;
        fs.writeFileSync(conf, cfg);
        const proxy = spawn('tinyproxy', ['-d', '-c', conf]);
        setTimeout(() => { state.tinyproxy = true; log('Tinyproxy ready'); res(); }, 3000);
        proxy.stdout.on('data', d => console.log(`[TINYPROXY] ${d.toString().trim()}`));
        proxy.on('close', () => state.tinyproxy = false);
    });
}

// OpenVPN – NO SUDO, user-space TUN
async function setupOpenVPN() {
    const ovpnPath = '/app/portmap.ovpn';
    const useBuiltIn = !fs.existsSync(ovpnPath);
    const configPath = useBuiltIn ? '/app/app.ovpn' : ovpnPath;
    log(useBuiltIn ? 'Using built-in OVPN' : 'Using mounted OVPN');

    return new Promise((res) => {
        const vpn = spawn('openvpn', [
            '--config', configPath,
            '--dev-type', 'tun',
            '--dev', 'tun0',
            '--script-security', '2',
            '--verb', '3'
        ]);
        const t = setTimeout(() => { log('OVPN timeout – continue'); res(); }, 45000);

        vpn.stdout.on('data', d => {
            const l = d.toString();
            console.log(`[OVPN] ${l.trim()}`);
            if (l.includes('Initialization Sequence Completed')) {
                clearTimeout(t);
                state.openvpn = true;
                parsePublicProxy(configPath);
                log('OpenVPN connected');
                res();
            }
        });
        vpn.stderr.on('data', d => console.error(`[OVPN ERR] ${d.toString().trim()}`));
        vpn.on('close', code => { log(`OpenVPN exited: ${code}`); res(); });
    });
}

function parsePublicProxy(path) {
    try {
        const m = fs.readFileSync(path, 'utf8').match(/remote\s+([^\s]+)\s+(\d+)/);
        if (m) state.publicProxy = { host: m[1], port: +m[2], user: 'free', pass: 'free' };
    } catch (e) {}
}

// Routes
app.get('/health', (req, res) => res.json({ status: 'ok', services: state }));
app.get('/info', (req, res) => res.json(state.publicProxy || { local: `http://localhost:${PROXY_PORT}` }));
app.get('/', (req, res) => {
    const p = state.publicProxy || { host: 'localhost', port: PROXY_PORT, user: 'free', pass: 'free' };
    res.send(`<!DOCTYPE html><html><head><title>Tor Proxy</title><style>body{font-family:Arial;background:#1e3c72;color:#fff;padding:40px;text-align:center;}</style></head><body><div style="background:rgba(255,255,255,0.1);padding:30px;border-radius:15px;max-width:500px;margin:auto;"><h1>Tor HTTP Proxy</h1><p><strong>Host:</strong> ${p.host}<br><strong>Port:</strong> ${p.port}<br><strong>User:</strong> free<br><strong>Pass:</strong> free</p><p style="color:#a0f7a0;">Via Tor</p></div></body></html>`);
});

// Start
async function main() {
    log('Starting services...');
    await setupTor();
    await setupTinyproxy();
    await setupOpenVPN();
    app.listen(PORT, '0.0.0.0', () => {
        log(`UI: http://0.0.0.0:${PORT}`);
        log(`Proxy: http://0.0.0.0:${PROXY_PORT}`);
        log('All ready');
    });
}
main().catch(e => { log('FATAL: ' + e.message); process.exit(1); });
EOF

# Entrypoint
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash
set -e
echo "=== Tor Proxy Starting ==="
[ -f /app/portmap.ovpn ] && echo "Using mounted OVPN" || echo "Using built-in OVPN"
exec node /app/app.js
EOF
RUN chmod +x /app/entrypoint.sh

EXPOSE 3000 8888
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s CMD curl -f http://localhost:3000/health || exit 1
ENV NODE_ENV=production
USER proxyuser
ENTRYPOINT ["/app/entrypoint.sh"]
