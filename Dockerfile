FROM node:18-bullseye-slim

# Install tools
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    openssh-client \
    autossh \
    curl \
    procps \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Create user
RUN useradd -m -s /bin/bash proxyuser && \
    mkdir -p /var/log/tinyproxy /var/run/tinyproxy /app/storage/Tor_Data /app/.ssh && \
    chown -R proxyuser:proxyuser /var/log/tinyproxy /var/run/tinyproxy /app

WORKDIR /app

# Node deps
RUN npm install --no-save express axios socks-proxy-agent

# === MAIN APP ===
RUN cat > /app/app.js << 'EOF'
const express = require('express');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

const app = express();
const PORT = process.env.PORT || 10000;
const PROXY_PORT = 8888;

let state = { tor: false, tinyproxy: false, sshTunnel: false, keepalive: false };
const processes = { tor: null, tinyproxy: null, autossh: null };
let keepaliveTimer = null;

function log(m) { console.log(`[${new Date().toISOString()}] ${m}`); }

// === Write app.pem from ENV at runtime ===
function writeSSHKey() {
    const pem = process.env.SSH_PRIVATE_KEY_PEM;
    if (!pem) {
        log('ERROR: SSH_PRIVATE_KEY_PEM not set');
        process.exit(1);
    }
    fs.writeFileSync('/app/.ssh/app.pem', pem.trim() + '\n');
    fs.chmodSync('/app/.ssh/app.pem', '600');
    log('app.pem written');
}

// === Convert PEM → OpenSSH (id_rsa) ===
function convertKey() {
    try {
        execSync('openssl rsa -in /app/.ssh/app.pem -out /app/.ssh/id_rsa -traditional 2>/dev/null', { stdio: 'ignore' });
        log('PEM → id_rsa converted');
    } catch (e) {
        try {
            execSync('openssl rsa -in /app/.ssh/app.pem -out /app/.ssh/id_rsa', { stdio: 'ignore' });
            log('PEM → id_rsa (standard)');
        } catch (e2) {
            log('Key conversion failed: ' + e2.message);
            process.exit(1);
        }
    }
    fs.chmodSync('/app/.ssh/id_rsa', '600');
}

// === SSH Config ===
function setupSSHConfig() {
    const config = `Host portmap
    HostName cdns-50919.portmap.host
    User cdns.first
    Port 50919
    IdentityFile /app/.ssh/id_rsa
    StrictHostKeyChecking no
    ServerAliveInterval 30
    ServerAliveCountMax 5
    ExitOnForwardFailure yes
    TCPKeepAlive yes
    IdentitiesOnly yes
`;
    fs.writeFileSync('/app/.ssh/config', config);
    fs.chmodSync('/app/.ssh/config', '600');
    log('SSH config ready');
}

// === Tor ===
function setupTor() {
    return new Promise(resolve => {
        if (processes.tor) return resolve();
        const torrc = '/app/storage/torrc';
        fs.writeFileSync(torrc, `SocksPort 0.0.0.0:9050\nDataDirectory /app/storage/Tor_Data\nLog notice stdout\n`);
        processes.tor = spawn('tor', ['-f', torrc]);
        const timeout = setTimeout(() => resolve(), 90000);
        processes.tor.stdout.on('data', d => {
            if (d.toString().includes('Bootstrapped 100%')) {
                clearTimeout(timeout);
                state.tor = true;
                log('Tor connected');
                resolve();
            }
        });
        processes.tor.on('close', () => { state.tor = false; });
    });
}

// === Tinyproxy ===
function setupTinyproxy() {
    return new Promise(resolve => {
        if (processes.tinyproxy) return resolve();
        const conf = '/app/storage/tinyproxy.conf';
        const config = `User proxyuser
Group proxyuser
Port ${PROXY_PORT}
Listen 0.0.0.0
LogFile "/var/log/tinyproxy/tinyproxy.log"
PidFile "/var/run/tinyproxy/tinyproxy.pid"
MaxClients 200
Allow 0.0.0.0/0
DisableViaHeader Yes
Upstream socks5 127.0.0.1:9050
`;
        fs.writeFileSync(conf, config);
        processes.tinyproxy = spawn('tinyproxy', ['-d', '-c', conf]);
        setTimeout(() => {
            state.tinyproxy = true;
            log(`Tinyproxy ready on :${PROXY_PORT}`);
            resolve();
        }, 3000);
        processes.tinyproxy.on('close', () => { state.tinyproxy = false; });
    });
}

// === SSH Tunnel ===
function setupSSHTunnel() {
    return new Promise(resolve => {
        if (processes.autossh) processes.autossh.kill();

        log('Starting SSH reverse tunnel...');
        processes.autossh = spawn('autossh', [
            '-M', '0',
            '-f', '-N',
            '-o', 'ServerAliveInterval=30',
            '-o', 'ServerAliveCountMax=5',
            '-R', '50919:localhost:8888',
            'portmap'
        ], { stdio: 'pipe' });

        let connected = false;
        const timeout = setTimeout(() => {
            if (!connected) {
                state.sshTunnel = true;
                log('SSH tunnel assumed active');
                resolve();
            }
        }, 60000);

        const checker = setInterval(() => {
            if (processes.autossh && !processes.autossh.killed) {
                require('net').createConnection(8888, '127.0.0.1')
                    .on('connect', () => {
                        if (!connected) {
                            clearInterval(checker);
                            clearTimeout(timeout);
                            connected = true;
                            state.sshTunnel = true;
                            log('SSH Tunnel LIVE → cdns-50919.portmap.host:50919');
                            resolve();
                        }
                    })
                    .on('error', () => {});
            }
        }, 5000);

        processes.autossh.on('exit', (code) => {
            state.sshTunnel = false;
            log(`SSH died (${code}). Restarting...`);
            setTimeout(setupSSHTunnel, 10000);
        });
    });
}

// === Keep-alive ===
async function keepAlive() {
    if (!state.tor) return;
    try {
        const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
        const res = await axios.get('https://httpbin.org/ip', { httpsAgent: agent, timeout: 15000 });
        log(`Keep-alive: ${res.data.origin}`);
    } catch (e) {
        log(`Keep-alive failed: ${e.message}`);
    }
}

function startKeepAlive() {
    keepaliveTimer = setInterval(keepAlive, 5 * 60 * 1000);
    setTimeout(keepAlive, 30000);
    log('Keep-alive started');
}

// === Web UI ===
app.get('/health', (req, res) => res.json({ status: state.tor && state.tinyproxy ? 'healthy' : 'degraded', ...state }));
app.get('/', (req, res) => res.send(`
<!DOCTYPE html>
<html><head><title>Tor Proxy</title>
<style>
  body{font-family: system-ui; background:#111; color:#0f0; padding:40px; text-align:center;}
  .box{background:#222; padding:30px; border-radius:15px; display:inline-block; margin:20px; min-width:500px;}
  code{background:#000; padding:15px; border-radius:8px; display:block; margin:15px 0; font-size:1.1em;}
  .on{color:#0f0;} .off{color:#f55;}
</style>
</head>
<body>
<h1>Tor → HTTP Proxy (SSH)</h1>
<div class="box">
  <p><strong>Public Proxy:</strong></p>
  <code>http://cdns-50919.portmap.host:50919</code>
  <p>Test:</p>
  <code>curl -x http://cdns-50919.portmap.host:50919 https://ifconfig.me</code>
  <p>Status: Tor=<span class="${state.tor?'on':'off'}">${state.tor?'ON':'OFF'}</span> | 
  Proxy=<span class="${state.tinyproxy?'on':'off'}">${state.tinyproxy?'ON':'OFF'}</span> | 
  Tunnel=<span class="${state.sshTunnel?'on':'off'}">${state.sshTunnel?'ON':'OFF'}</span></p>
</div>
</body></html>
`));

async function main() {
    log('Starting...');
    writeSSHKey();
    convertKey();
    setupSSHConfig();
    await setupTor();
    await setupTinyproxy();
    await setupSSHTunnel();
    startKeepAlive();

    app.listen(PORT, '0.0.0.0', () => {
        log(`Web UI: http://0.0.0.0:${PORT}`);
        log(`Proxy: http://0.0.0.0:${PROXY_PORT}`);
        log(`PUBLIC: http://cdns-50919.portmap.host:50919`);
        log('READY!');
    });
}

process.on('SIGTERM', () => {
    log('Shutting down...');
    Object.values(processes).forEach(p => p?.kill());
    process.exit(0);
});

main();
EOF

# === ENTRYPOINT ===
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash
set -e
echo "Tor + SSH Tunnel (app.pem from ENV)"
mkdir -p /app/storage /app/.ssh
chown proxyuser:proxyuser /app/storage /app/.ssh
exec node /app/app.js
EOF
RUN chmod +x /app/entrypoint.sh

EXPOSE 10000
HEALTHCHECK --interval=30s --timeout=10s CMD curl -f http://localhost:10000/health || exit 1

ENV NODE_ENV=production
USER proxyuser
ENTRYPOINT ["/app/entrypoint.sh"]
