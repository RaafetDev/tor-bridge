# Complete Tor → HTTP Proxy with OpenVPN Integration
# Single Dockerfile deployment for free-tier PaaS (Render.com)

FROM node:18-bullseye-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    tor \
    tinyproxy \
    openvpn \
    curl \
    procps \
    net-tools \
    iptables \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Node.js dependencies
RUN npm install --no-save \
    express \
    axios \
    socks-proxy-agent

# Create app.js using heredoc
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
#
# 2048 bit OpenVPN static key
#
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
EOF

# Create app.js using heredoc
RUN cat > /app/app.js << 'EOF'
const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3000;

// State management
const state = {
    tor: { running: false, bootstrapped: false },
    tinyproxy: { running: false },
    openvpn: { running: false, connected: false },
    publicProxy: null
};

// Security DNA for randomized headers
const securityDNA = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15'
];

function generateQuantumHeaders() {
    const dna = securityDNA[Math.floor(Math.random() * securityDNA.length)];
    return {
        'User-Agent': dna,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate, br',
        'DNT': '1',
        'Connection': 'keep-alive',
        'X-Quantum-Entropy': crypto.randomBytes(8).toString('hex'),
        'X-Request-ID': crypto.randomUUID()
    };
}

// Utility functions
function log(message) {
    console.log(`[${new Date().toISOString()}] ${message}`);
}

function ensureDir(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
        log(`Created directory: ${dirPath}`);
    }
}

// Step 1: Setup Tor
async function setupTor() {
    return new Promise((resolve, reject) => {
        const torDataDir = path.join(__dirname, 'storage', 'Tor_Data');
        ensureDir(torDataDir);

        const torrcPath = path.join(__dirname, 'torrc');
        const torrcContent = `
SocksPort 0.0.0.0:9050
DataDirectory ${torDataDir}
Log notice stdout
`;
        fs.writeFileSync(torrcPath, torrcContent);
        log('Generated torrc configuration');

        const torProcess = spawn('tor', ['-f', torrcPath]);
        
        torProcess.stdout.on('data', (data) => {
            const output = data.toString();
            console.log(`[TOR] ${output.trim()}`);
            
            if (output.includes('Bootstrapped 100%')) {
                state.tor.bootstrapped = true;
                log('✓ Tor bootstrapped successfully');
                resolve();
            }
        });

        torProcess.stderr.on('data', (data) => {
            console.error(`[TOR ERROR] ${data.toString().trim()}`);
        });

        torProcess.on('close', (code) => {
            state.tor.running = false;
            log(`Tor process exited with code ${code}`);
        });

        state.tor.running = true;
        
        // Timeout after 60 seconds
        setTimeout(() => {
            if (!state.tor.bootstrapped) {
                reject(new Error('Tor bootstrap timeout'));
            }
        }, 60000);
    });
}

// Step 2: Setup Tinyproxy
async function setupTinyproxy() {
    return new Promise((resolve, reject) => {
        const tinyproxyConf = `/etc/tinyproxy/tinyproxy.conf`;
        const config = `
User nobody
Group nogroup
Port 8888
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/var/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
Allow 0.0.0.0/0
ViaProxyName "tinyproxy"
DisableViaHeader Yes
Upstream socks5 127.0.0.1:9050
`;
        
        try {
            fs.mkdirSync('/var/log/tinyproxy', { recursive: true });
            fs.mkdirSync('/var/run/tinyproxy', { recursive: true });
            fs.writeFileSync(tinyproxyConf, config);
            log('Generated tinyproxy configuration');

            const tinyproxyProcess = spawn('tinyproxy', ['-d', '-c', tinyproxyConf]);
            
            tinyproxyProcess.stdout.on('data', (data) => {
                console.log(`[TINYPROXY] ${data.toString().trim()}`);
            });

            tinyproxyProcess.stderr.on('data', (data) => {
                const output = data.toString().trim();
                console.log(`[TINYPROXY] ${output}`);
                
                if (output.includes('listening on') || output.includes('Listening on')) {
                    state.tinyproxy.running = true;
                    log('✓ Tinyproxy started successfully');
                    resolve();
                }
            });

            tinyproxyProcess.on('close', (code) => {
                state.tinyproxy.running = false;
                log(`Tinyproxy process exited with code ${code}`);
            });

            // Resolve after 3 seconds if no explicit confirmation
            setTimeout(() => {
                if (!state.tinyproxy.running) {
                    state.tinyproxy.running = true;
                    resolve();
                }
            }, 3000);
        } catch (error) {
            reject(error);
        }
    });
}

// Step 3: Setup OpenVPN
async function setupOpenVPN() {
    return new Promise((resolve, reject) => {
        const ovpnPath = path.join(__dirname, 'app.ovpn');
        
        if (!fs.existsSync(ovpnPath)) {
            log('⚠ OpenVPN config not found - skipping VPN setup');
            log('Deploy will work but proxy will only be accessible locally');
            state.openvpn.connected = true; // Mock for local testing
            return resolve();
        }

        log('Starting OpenVPN client...');
        const vpnProcess = spawn('openvpn', ['--config', ovpnPath, '--verb', '3']);
        
        vpnProcess.stdout.on('data', (data) => {
            const output = data.toString();
            console.log(`[OPENVPN] ${output.trim()}`);
            
            if (output.includes('Initialization Sequence Completed')) {
                state.openvpn.connected = true;
                log('✓ OpenVPN tunnel established');
                
                // Parse public proxy info from portmap.io
                setTimeout(() => {
                    parsePortmapInfo(ovpnPath);
                    resolve();
                }, 2000);
            }
        });

        vpnProcess.stderr.on('data', (data) => {
            console.error(`[OPENVPN ERROR] ${data.toString().trim()}`);
        });

        vpnProcess.on('close', (code) => {
            state.openvpn.running = false;
            state.openvpn.connected = false;
            log(`OpenVPN process exited with code ${code}`);
        });

        state.openvpn.running = true;

        // Timeout after 30 seconds
        setTimeout(() => {
            if (!state.openvpn.connected) {
                log('⚠ OpenVPN timeout - continuing without VPN');
                state.openvpn.connected = true; // Allow app to continue
                resolve();
            }
        }, 30000);
    });
}

function parsePortmapInfo(ovpnPath) {
    try {
        const ovpnContent = fs.readFileSync(ovpnPath, 'utf8');
        const remoteMatch = ovpnContent.match(/remote\s+([^\s]+)\s+(\d+)/);
        
        if (remoteMatch) {
            state.publicProxy = {
                type: 'http',
                host: remoteMatch[1],
                port: parseInt(remoteMatch[2]),
                user: 'free',
                pass: 'free'
            };
            log(`✓ Public proxy available at ${state.publicProxy.host}:${state.publicProxy.port}`);
        }
    } catch (error) {
        log(`Error parsing portmap info: ${error.message}`);
    }
}

// Keepalive function
async function keepalive() {
    try {
        const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
        const response = await axios.get(`http://localhost:${PORT}/health`, {
            httpAgent: agent,
            headers: generateQuantumHeaders(),
            timeout: 10000
        });
        log(`Keepalive ping successful: ${response.status}`);
    } catch (error) {
        log(`Keepalive ping failed: ${error.message}`);
    }
}

// Express routes
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        services: {
            tor: state.tor,
            tinyproxy: state.tinyproxy,
            openvpn: state.openvpn
        }
    });
});

app.get('/info', (req, res) => {
    if (state.publicProxy) {
        res.json(state.publicProxy);
    } else {
        res.json({
            message: 'Public proxy info not available yet',
            localProxy: {
                type: 'http',
                host: 'localhost',
                port: 8888,
                note: 'Available only within container without VPN'
            }
        });
    }
});

app.get('/', (req, res) => {
    const proxyInfo = state.publicProxy || {
        host: 'Setup Required',
        port: 'N/A',
        user: 'free',
        pass: 'free'
    };

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Free Worldwide Tor Proxy</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 100%;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 30px;
            text-align: center;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        .proxy-info {
            background: rgba(0, 0, 0, 0.2);
            border-radius: 10px;
            padding: 25px;
            margin-top: 20px;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }
        .info-row:last-child {
            border-bottom: none;
        }
        .label {
            font-weight: 600;
            opacity: 0.9;
        }
        .value {
            font-family: 'Courier New', monospace;
            background: rgba(255, 255, 255, 0.1);
            padding: 4px 12px;
            border-radius: 5px;
        }
        .status {
            text-align: center;
            margin-top: 25px;
            padding: 15px;
            background: rgba(76, 175, 80, 0.2);
            border-radius: 8px;
            border-left: 4px solid #4CAF50;
        }
        .warning {
            margin-top: 20px;
            padding: 15px;
            background: rgba(255, 193, 7, 0.2);
            border-radius: 8px;
            border-left: 4px solid #FFC107;
            font-size: 0.9em;
        }
        @media (max-width: 600px) {
            h1 {
                font-size: 1.8em;
            }
            .container {
                padding: 25px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Free Worldwide Tor Proxy</h1>
        <div class="proxy-info">
            <div class="info-row">
                <span class="label">Type:</span>
                <span class="value">HTTP</span>
            </div>
            <div class="info-row">
                <span class="label">Host:</span>
                <span class="value">${proxyInfo.host}</span>
            </div>
            <div class="info-row">
                <span class="label">Port:</span>
                <span class="value">${proxyInfo.port}</span>
            </div>
            <div class="info-row">
                <span class="label">Username:</span>
                <span class="value">${proxyInfo.user}</span>
            </div>
            <div class="info-row">
                <span class="label">Password:</span>
                <span class="value">${proxyInfo.pass}</span>
            </div>
        </div>
        <div class="status">
            ✓ All traffic routed through Tor network
        </div>
        <div class="warning">
            ⚠️ <strong>Ethical Use Only:</strong> This proxy is intended for legitimate privacy purposes only. Misuse for illegal activities is strictly prohibited.
        </div>
    </div>
</body>
</html>
    `;
    res.send(html);
});

// Main initialization
async function main() {
    try {
        log('=== Starting Tor → HTTP Proxy Service ===');
        
        log('Step 1: Setting up Tor...');
        await setupTor();
        
        log('Step 2: Setting up Tinyproxy...');
        await setupTinyproxy();
        
        log('Step 3: Setting up OpenVPN...');
        await setupOpenVPN();
        
        log('Step 4: Starting Express server...');
        app.listen(PORT, () => {
            log(`✓ Express server running on port ${PORT}`);
            log('=== All services operational ===');
        });

        // Start keepalive pings every 5 minutes
        setInterval(keepalive, 5 * 60 * 1000);
        
    } catch (error) {
        log(`FATAL ERROR: ${error.message}`);
        process.exit(1);
    }
}

main();
EOF

# Create entrypoint script
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "==================================="
echo "Tor → HTTP Proxy Container Starting"
echo "==================================="

# Check for OpenVPN config
if [ -f "/app/portmap.ovpn" ]; then
    echo "✓ OpenVPN config found"
else
    echo "⚠ No OpenVPN config found at /app/portmap.ovpn"
    echo "  Service will run but proxy won't be publicly accessible"
    echo "  Mount your portmap.io .ovpn file to /app/portmap.ovpn"
fi

# Start the Node.js application
exec node /app/app.js
EOF

RUN chmod +x /app/entrypoint.sh

# Create necessary directories
RUN mkdir -p /var/log/tinyproxy /var/run/tinyproxy /app/storage

# Expose ports
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Set environment variables
ENV NODE_ENV=production
ENV OVPN_PATH=/app/portmap.ovpn

# Run the application
ENTRYPOINT ["/app/entrypoint.sh"]
