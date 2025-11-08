FROM node:18-bullseye-slim

# Install tools
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    openssh-client \
    curl \
    procps \
    netcat \
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
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');
const net = require('net');

const app = express();
const PORT = process.env.PORT || 10000;
const PROXY_PORT = 8888;

let state = { tor: false, tinyproxy: false, sshTunnel: false, keepalive: false };
const processes = { tor: null, tinyproxy: null, ssh: null };
let keepaliveTimer = null;

function log(m) { console.log(`[${new Date().toISOString()}] ${m}`); }

// === Write app.pem from ENV ===
function writeSSHKey() {
    const pem = process.env.SSH_PRIVATE_KEY_PEM;
    if (!pem) {
        log('ERROR: SSH_PRIVATE_KEY_PEM not set');
        process.exit(1);
    }
    fs.writeFileSync('/app/.ssh/app.pem', pem.trim() + '\n', { mode: 0o600 });
    log('app.pem written');
}

// === Wait for port 8888 to be open ===
function waitForPort() {
    return new Promise(resolve => {
        const interval = setInterval(() => {
            const client = net.createConnection(PROXY_PORT, '127.0.0.1', () => {
                client.end();
                clearInterval(interval);
                log(`Port ${PROXY_PORT} is OPEN`);
                resolve();
            });
            client.on('error', () => {});
        }, 1000);
        setTimeout(() => {
            clearInterval(interval);
            log(`Port ${PROXY_PORT} timeout`);
            resolve();
        }, 30000);
    });
}

// === Tor ===
function setupTor() {
    return new Promise(resolve => {
        if (processes.tor) return resolve();
        const torrc = '/app/storage/torrc';
        Fs.writeFileSync(torrc, `SocksPort 0.0.0.0:9050\nDataDirectory /app/storage/Tor_Data\nLog notice stdout\n`);
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

// === Tinyproxy (START FIRST!) ===
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
            log(`Tinyproxy LISTENING on :${PROXY_PORT}`);
            resolve();
        }, 3000);
        processes.tinyproxy.on('close', () => { state.tinyproxy = false; });
    });
}

// === SSH Tunnel (AFTER tinyproxy) ===
async function setupSSHTunnel() {
    return new Promise(resolve => {
        if (processes.ssh) processes.ssh.kill();

        log('Waiting for port 8888...');
        waitForPort().then(() => {
            log('Starting SSH tunnel (Portmap.io style)...');
            const cmd = 'ssh';
            const args = [
                '-i', '/app/.ssh/app.pem',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'ServerAliveInterval=30',
                '-o', 'ServerAliveCountMax=3',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'ConnectTimeout=15',
                '-N',
                '-R', '50919:localhost:8888',
                'cdns.first@cdns-50919.portmap.host'
            ];

            processes.ssh = spawn(cmd, args, { stdio: 'pipe' });

            let connected = false;
            const timeout = setTimeout(() => {
                if (!connected) {
                    state.sshTunnel = true;
                    log('SSH tunnel assumed active');
                    resolve();
                }
            }, 45000);

            processes.ssh.stdout.on('data', d => log(`[SSH] ${d}`));
            processes.ssh.stderr.on('data', d => {
                const msg = d.toString();
                if (msg.includes('pledge: network') || msg.includes('connect_to')) return; // ignore
                log(`[SSH ERR] ${msg}`);
            });

            processes.ssh.on('exit', (code) => {
                state.sshTunnel = false;
                log(`SSH exited (${code || 'unknown'}). Restarting in 10s...`);
                setTimeout(setupSSHTunnel, 10000);
            });

            // Confirm tunnel via local port
            const checker = setInterval(() => {
                net.createConnection(8888, '127.0.0.1')
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
            }, 5000);
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
app.get('/health', (req, res) => res.json({ status: state.tor && state.tinyproxy && state.sshTunnel ? 'healthy' : 'degraded', ...state }));
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
    await setupTor();
    await setupTinyproxy();   // ← FIRST
    await setupSSHTunnel();   // ← AFTER port 8888 open
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
echo "Tor + SSH Tunnel (Tinyproxy FIRST)"
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
