FROM node:18-bullseye-slim

# Install system deps
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    openvpn \
    curl \
    wget \
    procps \
    net-tools \
    iproute2 \
    iptables \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Setup TUN device support
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 2>/dev/null || true && \
    chmod 666 /dev/net/tun 2>/dev/null || true

# Create user with sudo privileges
RUN useradd -m -s /bin/bash proxyuser && \
    echo "proxyuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /var/log/tinyproxy /var/run/tinyproxy /app/storage/Tor_Data && \
    chown -R proxyuser:proxyuser /var/log/tinyproxy /var/run/tinyproxy /app/storage

WORKDIR /app

# Install Node packages
RUN npm install --no-save express axios socks-proxy-agent

# Create storage directory
RUN mkdir -p /app/storage

# === OpenVPN Config (Portmap.io) ===
RUN cat > /app/app.ovpn << 'EOF'
client
nobind
dev tun
key-direction 1
remote-cert-tls server
remote 193.161.193.99 1194 tcp

<key>
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDH/EnB+hm/9IQU
wXFxQKJz3rjCgynikUySJdkI/2k1hJRduKTOmjKGWc4Pd6cASriECrmOgHabhGye
IK3ouAV0oDNH6coaqEHLBsXN02v+smKp5v7/y6Mmr39Fi+leOBOAvFTLEqEB4pJf
AARGm/usELADFrBY+mjYw8xltfMvuRv1+6odJTMj37XxeR80B7MHrqnYMCVZwTaf
REXGDIUp/UPqsjAXhp7sj3MEifKKyXOx+UYOqA+EOerR9JqDcpj8gIONzjgQRxjp
Neprs6zp6RoZgD+JYC4c8A/MhZvSTKvM77qNtVdAHDzyx6+2Sea7QyMOW2ZzF0J5
HQQEmvzzAgMBAAECggEARLDI6tpLZu4HQhPRsdtIEXGSV6lyxRIwUVCztA36prnD
tk9aOGapbRFCoHhyQbzolN4ULzi7xJ4fKs9BvNoccZsnEg/g7fgWJTTN021HvmOq
VP51Xwokn4CPQCWXAlhThpfprhjXeczHht78GP6x2r+enWj5KI7WXYIfXl45Sg34
0xKMRy/wgPJcAQ+j9S5kC5TlDeVaySLcmJ2eHa/hLzHANbKsFKMCNKFcNvIY//H0
M1J2cx6F5VYws6G8X97au/v2A5HFQ7EACRAFDhRB2+AYQ/vrGL48iEN9DfQ7pkDr
jFOKU7nVwg1jVvE08Q6zzb4RK/BdL8Q8IADKuboX2QKBgQDsIQMStmOcHQPjY2Oh
/PY7VMejI3DMwPSqp1XOrJoCBwoeRGqOCNLSqUi5j684KRl74sCiolNL0GplhvoQ
PqCXTKUsLt3aF1DZvADFj1Z1/JmGwGPIq0Bkt+iQ4u7rmC34LLjBeZ1C3qmQiOhB
h42PscCVofT5UdUb+dB6S0au2QKBgQDY0KDTeUp2Dbk46HzdWrShq1Q9e+LZT4Nc
vSaEezjgxs+O2eUmY8GLF13NCsS5EsHcZg7jDpC+IagGDdRhNRKSld5VD9iJt5cF
ww/gBDQ6l9X8NnZ+Wseba+L7FtBM1mTZbNU5jq/80XQoqOSOFcQL4f9vPDKOFfpR
QUqhaCqCqwKBgF/mlHHwI4qO+jpK7ncm3vZ/20j1puVx5Ky+o4n57d6u7zwVu1UO
XllyqXe71IUxpAj9shEbbksXTW8In90jImPwnBDSxAXEfHDB+2pBafMncU8aKiyg
6Nk/HDRkBncm6lymBS+G7gjvl9x8zh93J1ZZ8gaTrYPo6W2gSzyv//gZAoGBAKO/
LTeJ60qtoq3wKB2lW7aeBslIv1MQUk3ALU7xIUvh2vAwcHhF7u51f0pUT67XE8K4
8ZVacsal9Jhd6YBg7N34gioMBaY9GbooT90IT8nQ0rPhDizvssEXAh5QZJEjepcb
Mw59TTzLk8cBh1wn5CB1Vs1T0Xqt7pdfkFXGrhRxAoGAG8f0hmBDVgYL1oWL4hXj
RxaDVJAHNMrT9OKHg20fPmWM0/vPuNvosz2y8NF93Woge6qc6l2z72QzsOdqs2zc
C3G68Ryt+xNnPBLY/+i0AXZdQG3TexNna2qhorzwCQJwXCm/qAKr+12jFWrR2Jq1
gRFjDN1jLHhvPJo1BO6f76E=
-----END PRIVATE KEY-----
</key>
<cert>
-----BEGIN CERTIFICATE-----
MIIDVzCCAj+gAwIBAgIRAKCq+cGP2dLzuomoq0JHbAAwDQYJKoZIhvcNAQELBQAw
FTETMBEGA1UEAwwKUG9ydG1hcCBDQTAeFw0yNTExMDcwMDI1MDBaFw0zNTExMDUw
MDI1MDBaMBUxEzARBgNVBAMMCmNkbnMuZmlyc3QwggEiMA0GCSqGSIb3DQEBAQUA
A4IBDwAwggEKAoIBAQDH/EnB+hm/9IQUwXFxQKJz3rjCgynikUySJdkI/2k1hJRd
uKTOmjKGWc4Pd6cASriECrmOgHabhGyeIK3ouAV0oDNH6coaqEHLBsXN02v+smKp
5v7/y6Mmr39Fi+leOBOAvFTLEqEB4pJfAARGm/usELADFrBY+mjYw8xltfMvuRv1
+6odJTMj37XxeR80B7MHrqnYMCVZwTafREXGDIUp/UPqsjAXhp7sj3MEifKKyXOx
+UYOqA+EOerR9JqDcpj8gIONzjgQRxjpNeprs6zp6RoZgD+JYC4c8A/MhZvSTKvM
77qNtVdAHDzyx6+2Sea7QyMOW2ZzF0J5HQQEmvzzAgMBAAGjgaEwgZ4wCQYDVR0T
BAIwADAdBgNVHQ4EFgQUq620UUaCW9ZD2riCE7j4k0FStM4wUAYDVR0jBEkwR4AU
XsXvH1KXcobpC1m4IpL8q2t/AJ+hGaQXMBUxEzARBgNVBAMMClBvcnRtYXAgQ0GC
FErSBwvIKD3Fz83SpDtqL4/Q8k2oMBMGA1UdJQQMMAoGCCsGAQUFBwMCMAsGA1Ud
DwQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAQEAmE+5exUxS6wJ0K5x64dXlOLq1ikz
i5X0JrI8iIcwHLrrMSMvKpEQtFUQRp3L1OmDXCgMla76UaoYGp1pb3vHzFJtHkPy
ash6XE8wdrX1oo7n4RDi7wQx6QoVo5jkkQN28h5P9VmUMm6PIs7qUlQeMzMqbIyN
eK6YlqxFHHOTprf0rULeS00PKCh8nvpFJadzzF42ztgGdFM6gVt06SdCb/EiuJYu
h0trvKpbzIw8W5baKzonmGC5WClEEBqpv9dFzzPyk5r69UuF6NiTlvhNs4zyI7yG
vPfETykwSRkg37wEPfmit+zn5b49xRRUTsCNW7cwxr46012cF/mG4xoT/w==
-----END CERTIFICATE-----
</cert>
<ca>
-----BEGIN CERTIFICATE-----
MIIDSDCCAjCgAwIBAgIUStIHC8goPcXPzdKkO2ovj9DyTagwDQYJKoZIhvcNAQEL
BQAwFTETMBEGA1UEAwwKUG9ydG1hcCBDQTAeFw0yNTEwMzAwMTE3NDFaFw0zNTEw
MjgwMTE3NDFaMBUxEzARBgNVBAMMClBvcnRtYXAgQ0EwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQCnSBLhf3eDHOc2a6dl4YcdcIsFLNmLYdZo2J1qBp/N
MoZrpFWY1qf0VpphArqkaD4UY+8uOPyfZ+3yxhPOVZzGsYSYykpkIWWGi7HwBe6x
PpjLTT3XvBRSz6KHGUcXldeQxJKSmS9blq1+JcI3QRgVUL+Q3/HrvrAyUVTmzMip
aKe1m2L6h78dfLs8BOjxHk29sJiQHstNrMmBJehy4VdltzNGGAraFQLYaqIUWxyx
2AZcJcgHOYzzf+T8KR8ig69PbXgFC50dZH6uiPv0f2PEcXSQ4o5bY2e4kurFEuAN
KJTa/Y3crJ897CxpHdplgJcEomML1y3bxE/QtNNF2eMNAgMBAAGjgY8wgYwwHQYD
VR0OBBYEFF7F7x9Sl3KG6QtZuCKS/KtrfwCfMFAGA1UdIwRJMEeAFF7F7x9Sl3KG
6QtZuCKS/KtrfwCfoRmkFzAVMRMwEQYDVQQDDApQb3J0bWFwIENBghRK0gcLyCg9
xc/N0qQ7ai+P0PJNqDAMBgNVHRMEBTADAQH/MAsGA1UdDwQEAwIBBjANBgkqhkiG
9w0BAQsFAAOCAQEAHRHTX724CjGcfVcE/AscysAYXlVXmc48vKx9kqJiqyG7+mBt
gW5aIIqHIDGCyIJD47GRH6E0Rb19opGru53KsHUhiMXeSCmH+N/zew35l3R3cyLZ
fAHFlqeeLve5g7ozPWgpRoCISVoP8Us2jggwheOYNtTU4C9lVr2ojejmIz2rq03p
p6rHY0AfwzZRfN5CQkXAUauVvwo5QupmUQ1z8aBnW9WZLCLu114wpqSqMaTzkD89
aenMJoWMRnJhW1yt0aL3c/0b+EzfaRePE+i0SpjIYdXPrcRXLayJZygzBgl2nUaa
Yn4yh0mVdscdM7FLTCq8PWQDCmr6dgsRzdMLPA==
-----END CERTIFICATE-----
</ca>
<tls-auth>
-----BEGIN OpenVPN Static key V1-----
42bb453ee0df769b134e57435c88a745
927d7fd254987077bdf822567410ed73
f816335742f5737b0ad1e290ebe4e669
1a8edad3f23aff0c4872172f1e3c30d2
025cddbfd2dfdcecb3ef2f1f4e531c60
1e9c48e1abe96c46c80eaa5f121a72b5
e7b194a6a0abc06fbc736abc41122f5d
aa0c7ddcfc80455983ac7e6cb005d0c7
7ef5ed9c20cebe4481a733a5b4e63ba8
74a0710bcd0b732d5b79ef6e2032c0c2
6e1cbe01873367524a28d582901ceed1
241fe087a8e84467c9c790c7af719622
413fcc77b130629258db8a8e6678f53c
7cd213dc82e5b613ca310642cfbb6cb5
63111511e467f45417d9950035827d30
43b13e9e01f0c42481edb1fe1808806b
-----END OpenVPN Static key V1-----
</tls-auth>
key-direction 1
cipher AES-128-CBC
data-ciphers AES-256-GCM:AES-128-GCM:AES-128-CBC
EOF

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

let state = { 
    tor: false, 
    tinyproxy: false, 
    openvpn: false,
    publicProxy: null,
    keepaliveActive: false
};

const processes = { tor: null, tinyproxy: null, openvpn: null };
let keepaliveTimer = null;

function log(m) { console.log(`[${new Date().toISOString()}] ${m}`); }

// Setup TUN device
function ensureTun() {
    try {
        execSync('mkdir -p /dev/net 2>/dev/null || true', { stdio: 'ignore' });
        execSync('mknod /dev/net/tun c 10 200 2>/dev/null || true', { stdio: 'ignore' });
        execSync('chmod 666 /dev/net/tun 2>/dev/null || true', { stdio: 'ignore' });
        log('✓ TUN device ready');
    } catch (e) {
        log(`⚠ TUN warning: ${e.message}`);
    }
}

// Tor setup
function setupTor() {
    return new Promise((resolve, reject) => {
        if (processes.tor) {
            log('Tor already running');
            return resolve();
        }

        const torrc = '/app/storage/torrc';
        fs.writeFileSync(torrc, `SocksPort 0.0.0.0:9050\nDataDirectory /app/storage/Tor_Data\nLog notice stdout\n`);
        
        processes.tor = spawn('tor', ['-f', torrc]);
        const timeout = setTimeout(() => reject('Tor timeout'), 90000);
        
        processes.tor.stdout.on('data', d => {
            const line = d.toString();
            if (line.includes('Bootstrapped 100%')) {
                clearTimeout(timeout);
                state.tor = true;
                log('✓ Tor connected');
                resolve();
            }
        });
        
        processes.tor.on('close', () => {
            state.tor = false;
            processes.tor = null;
            log('Tor closed');
        });
    });
}

// Tinyproxy setup
function setupTinyproxy() {
    return new Promise((resolve) => {
        if (processes.tinyproxy) {
            log('Tinyproxy already running');
            return resolve();
        }

        const conf = '/app/storage/tinyproxy.conf';
        const config = `User proxyuser
Group proxyuser
Port ${PROXY_PORT}
Listen 0.0.0.0
LogFile "/var/log/tinyproxy/tinyproxy.log"
PidFile "/var/run/tinyproxy/tinyproxy.pid"
MaxClients 100
Allow 0.0.0.0/0
DisableViaHeader Yes
Upstream socks5 127.0.0.1:9050
`;
        fs.writeFileSync(conf, config);
        
        processes.tinyproxy = spawn('tinyproxy', ['-d', '-c', conf]);
        
        setTimeout(() => {
            state.tinyproxy = true;
            log('✓ Tinyproxy ready');
            resolve();
        }, 3000);
        
        processes.tinyproxy.on('close', () => {
            state.tinyproxy = false;
            processes.tinyproxy = null;
            log('Tinyproxy closed');
        });
    });
}

// OpenVPN setup
function setupOpenVPN() {
    return new Promise((resolve) => {
        if (processes.openvpn) {
            log('OpenVPN already running');
            return resolve();
        }

        ensureTun();
        
        const ovpnPath = '/app/portmap.ovpn';
        const configPath = fs.existsSync(ovpnPath) ? ovpnPath : '/app/app.ovpn';
        
        log(`Using config: ${configPath}`);
        
        processes.openvpn = spawn('openvpn', [
            '--config', configPath,
            '--dev', 'tun0',
            '--script-security', '2',
            '--verb', '3'
        ]);
        
        const timeout = setTimeout(() => {
            log('OpenVPN timeout - continuing');
            resolve();
        }, 45000);
        
        processes.openvpn.stdout.on('data', d => {
            const line = d.toString();
            console.log(`[VPN] ${line.trim()}`);
            if (line.includes('Initialization Sequence Completed')) {
                clearTimeout(timeout);
                state.openvpn = true;
                parsePublicProxy(configPath);
                log('✓ OpenVPN connected');
                resolve();
            }
        });
        
        processes.openvpn.stderr.on('data', d => {
            console.error(`[VPN ERR] ${d.toString().trim()}`);
        });
        
        processes.openvpn.on('close', code => {
            state.openvpn = false;
            processes.openvpn = null;
            log(`OpenVPN closed: ${code}`);
            resolve();
        });
    });
}

// Parse public proxy info from OVPN
function parsePublicProxy(path) {
    try {
        const content = fs.readFileSync(path, 'utf8');
        const match = content.match(/remote\s+([^\s]+)\s+(\d+)/);
        if (match) {
            state.publicProxy = {
                host: match[1],
                port: parseInt(match[2]),
                type: 'http',
                username: 'free',
                password: 'free'
            };
            log(`✓ Public proxy: ${match[1]}:${match[2]}`);
        }
    } catch (e) {
        log(`Parse proxy error: ${e.message}`);
    }
}

// Keep-alive job to prevent Render sleep
async function keepAlive() {
    if (!state.keepaliveActive) return;
    
    try {
        const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
        const sites = [
            'https://www.google.com',
            'https://www.wikipedia.org',
            'https://www.github.com',
            'https://www.stackoverflow.com'
        ];
        
        const site = sites[Math.floor(Math.random() * sites.length)];
        const response = await axios.get(site, {
            httpAgent: agent,
            httpsAgent: agent,
            timeout: 15000,
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
        });
        
        log(`✓ Keep-alive: ${site} [${response.status}]`);
    } catch (e) {
        log(`⚠ Keep-alive failed: ${e.message}`);
    }
}

// Start keep-alive job
function startKeepAlive() {
    if (keepaliveTimer) return;
    
    state.keepaliveActive = true;
    keepaliveTimer = setInterval(() => keepAlive(), 5 * 60 * 1000); // Every 5 minutes
    log('✓ Keep-alive job started (5min interval)');
    
    // Initial run after 30s
    setTimeout(() => keepAlive(), 30000);
}

// Routes
app.get('/health', (req, res) => {
    res.json({ 
        status: state.tor && state.tinyproxy ? 'healthy' : 'degraded',
        services: state 
    });
});

app.get('/info', (req, res) => {
    res.json(state.publicProxy || { error: 'No public proxy available' });
});

app.get('/', (req, res) => {
    const proxy = state.publicProxy;
    const status = state.openvpn ? 'success' : 'warning';
    const statusText = state.openvpn ? '✓ CONNECTED' : '⚠ VPN Unavailable';
    
    res.send(`<!DOCTYPE html>
<html>
<head>
    <title>🧅 Tor Proxy Service</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 40px auto;
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(20px);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 {
            font-size: 3em;
            text-align: center;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .subtitle {
            text-align: center;
            opacity: 0.9;
            margin-bottom: 40px;
            font-size: 1.2em;
        }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .status-card {
            background: rgba(255,255,255,0.15);
            padding: 20px;
            border-radius: 15px;
            text-align: center;
        }
        .status-card .icon { font-size: 2em; margin-bottom: 10px; }
        .status-card .label { opacity: 0.8; font-size: 0.9em; }
        .status-card .value { 
            font-size: 1.2em; 
            font-weight: bold; 
            margin-top: 5px;
        }
        .success { color: #4ade80; }
        .warning { color: #fbbf24; }
        .proxy-box {
            background: rgba(0,0,0,0.3);
            padding: 30px;
            border-radius: 15px;
            margin: 30px 0;
        }
        .proxy-box h2 {
            margin-bottom: 20px;
            font-size: 1.5em;
        }
        .proxy-info {
            display: grid;
            grid-template-columns: 120px 1fr;
            gap: 15px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 1.1em;
        }
        .proxy-info .key { opacity: 0.8; }
        .proxy-info .val { 
            font-weight: bold;
            color: #4ade80;
        }
        .usage-section {
            background: rgba(255,255,255,0.1);
            padding: 25px;
            border-radius: 15px;
            margin-top: 20px;
        }
        .usage-section h3 {
            margin-bottom: 15px;
        }
        .code {
            background: rgba(0,0,0,0.4);
            padding: 15px;
            border-radius: 8px;
            font-family: 'Monaco', monospace;
            font-size: 0.9em;
            overflow-x: auto;
            margin-top: 10px;
        }
        .badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
            margin-top: 10px;
        }
        .badge.active { background: #4ade80; color: #000; }
        @media (max-width: 768px) {
            h1 { font-size: 2em; }
            .container { padding: 25px; }
            .proxy-info { grid-template-columns: 1fr; gap: 10px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧅 Tor Proxy</h1>
        <p class="subtitle">Worldwide Anonymous HTTP Proxy</p>
        
        <div class="status-grid">
            <div class="status-card">
                <div class="icon">🌐</div>
                <div class="label">Tor Network</div>
                <div class="value ${state.tor ? 'success' : 'warning'}">
                    ${state.tor ? '✓ Connected' : '⚠ Offline'}
                </div>
            </div>
            <div class="status-card">
                <div class="icon">🔄</div>
                <div class="label">HTTP Proxy</div>
                <div class="value ${state.tinyproxy ? 'success' : 'warning'}">
                    ${state.tinyproxy ? '✓ Running' : '⚠ Stopped'}
                </div>
            </div>
            <div class="status-card">
                <div class="icon">🔐</div>
                <div class="label">VPN Tunnel</div>
                <div class="value ${status}">
                    ${statusText}
                </div>
            </div>
            <div class="status-card">
                <div class="icon">⏱️</div>
                <div class="label">Keep-Alive</div>
                <div class="value success">
                    ✓ Active
                </div>
            </div>
        </div>

        ${proxy ? `
        <div class="proxy-box">
            <h2>🌍 Public HTTP Proxy</h2>
            <div class="proxy-info">
                <div class="key">Type:</div>
                <div class="val">HTTP</div>
                <div class="key">Host:</div>
                <div class="val">${proxy.host}</div>
                <div class="key">Port:</div>
                <div class="val">${proxy.port}</div>
                <div class="key">Username:</div>
                <div class="val">${proxy.username}</div>
                <div class="key">Password:</div>
                <div class="val">${proxy.password}</div>
            </div>
            <span class="badge active">FREE WORLDWIDE ACCESS</span>
        </div>

        <div class="usage-section">
            <h3>🐍 Python Usage</h3>
            <div class="code">proxies = {<br>&nbsp;&nbsp;'http': 'http://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port}',<br>&nbsp;&nbsp;'https': 'http://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port}'<br>}<br>r = requests.get('https://ipinfo.io/json', proxies=proxies)<br>print(r.json())</div>
        </div>

        <div class="usage-section">
            <h3>💻 cURL Usage</h3>
            <div class="code">curl -x http://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port} https://ipinfo.io/json</div>
        </div>

        <div class="usage-section">
            <h3>🦊 Firefox Setup</h3>
            <div class="code">Settings → Network Settings → Manual proxy<br>HTTP Proxy: ${proxy.host}<br>Port: ${proxy.port}<br>Username: ${proxy.username}<br>Password: ${proxy.password}</div>
        </div>
        ` : `
        <div class="proxy-box">
            <h2>⚠️ Public Proxy Unavailable</h2>
            <p style="opacity: 0.8;">VPN tunnel is establishing connection. Tor proxy still working internally.</p>
        </div>
        `}
    </div>
</body>
</html>`);
});

// Main startup
async function main() {
    log('════════════════════════════════════════');
    log('   🧅 TOR PROXY SERVICE - IA V99');
    log('════════════════════════════════════════');
    
    try {
        // Start services in sequence
        await setupTor();
        await setupTinyproxy();
        await setupOpenVPN();
        
        // Start keep-alive
        startKeepAlive();
        
        // Start web server
        app.listen(PORT, '0.0.0.0', () => {
            log('════════════════════════════════════════');
            log(`✓ Web UI: http://0.0.0.0:${PORT}`);
            log(`✓ Local Proxy: http://0.0.0.0:${PROXY_PORT}`);
            if (state.publicProxy) {
                log(`✓ Public Proxy: ${state.publicProxy.host}:${state.publicProxy.port}`);
            }
            log('════════════════════════════════════════');
            log('🎉 ALL SYSTEMS READY!');
        });
    } catch (e) {
        log(`❌ FATAL: ${e.message}`);
        process.exit(1);
    }
}

// Graceful shutdown
process.on('SIGTERM', () => {
    log('Shutting down gracefully...');
    if (keepaliveTimer) clearInterval(keepaliveTimer);
    Object.values(processes).forEach(p => p && p.kill());
    process.exit(0);
});

main();
EOF

# Entrypoint
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash
set -e
echo "════════════════════════════════════════"
echo "   🧅 TOR PROXY - IA V99"
echo "   Think Outside The Box"
echo "════════════════════════════════════════"
echo ""
exec node /app/app.js
EOF
RUN chmod +x /app/entrypoint.sh

EXPOSE 10000
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s \
    CMD curl -f http://localhost:${PORT:-10000}/health || exit 1

ENV NODE_ENV=production
USER proxyuser
ENTRYPOINT ["/app/entrypoint.sh"]
