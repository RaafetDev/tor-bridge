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
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user + fix permissions
RUN useradd -m -s /bin/bash proxyuser && \
    echo "proxyuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/proxyuser && \
    mkdir -p /var/log/tinyproxy /var/run/tinyproxy /app/storage/Tor_Data && \
    chown -R proxyuser:proxyuser /var/log/tinyproxy /var/run/tinyproxy /app/storage

# Set working directory
WORKDIR /app

# Install Node.js dependencies
RUN npm install --no-save express axios socks-proxy-agent

# === KEEP: Create app.ovpn config file ===
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
ash6XE8wdrX1oo7n4RDi7wQx6QoVo5jkkQN28h5P9VmUMm6PIs7qUlQeMzMqbIyn
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
fAHFlqZeeLve5g7ozPWgpRoCISVoP8Us2jggwheOYNtTU4C9lVr2ojejmIz2rq03p
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
EOF

# === Create app.js (single file, no duplicates) ===
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
const PROXY_PORT = 8888;

// State
let state = {
    tor: { running: false, bootstrapped: false },
    tinyproxy: { running: false },
    openvpn: { running: false, connected: false },
    publicProxy: null
};

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

// Tor setup
async function setupTor() {
    return new Promise((resolve, reject) => {
        const torDataDir = '/app/storage/Tor_Data';
        const torrcPath = '/app/storage/torrc';  // MOVED TO WRITABLE DIR
        const torrcContent = `SocksPort 0.0.0.0:9050\nDataDirectory ${torDataDir}\nLog notice stdout\n`;
        try {
            fs.writeFileSync(torrcPath, torrcContent);
            log('Generated torrc');
        } catch (err) {
            log(`Failed to write torrc: ${err.message}`);
            return reject(err);
        }

        const tor = spawn('tor', ['-f', torrcPath]);
        const timeout = setTimeout(() => reject(new Error('Tor timeout')), 90000);

        tor.stdout.on('data', data => {
            const line = data.toString();
            console.log(`[TOR] ${line.trim()}`);
            if (line.includes('Bootstrapped 100%')) {
                clearTimeout(timeout);
                state.tor.bootstrapped = true;
                log('Tor bootstrapped');
                resolve();
            }
        });

        tor.stderr.on('data', data => console.error(`[TOR ERR] ${data.toString().trim()}`));
        tor.on('close', code => {
            state.tor.running = false;
            log(`Tor exited: ${code}`);
        });
        state.tor.running = true;
    });
}

// Tinyproxy setup
async function setupTinyproxy() {
    return new Promise((resolve) => {
        const confPath = '/app/storage/tinyproxy.conf';  // MOVED TO WRITABLE DIR
        const config = `User proxyuser\nGroup proxyuser\nPort ${PROXY_PORT}\nListen 0.0.0.0\nTimeout 600\nLogFile "/var/log/tinyproxy/tinyproxy.log"\nPidFile "/var/run/tinyproxy/tinyproxy.pid"\nMaxClients 50\nMinSpareServers 2\nMaxSpareServers 10\nStartServers 5\nAllow 0.0.0.0/0\nDisableViaHeader Yes\nUpstream socks5 127.0.0.1:9050\n`;
        fs.writeFileSync(confPath, config);
        log('Generated tinyproxy.conf');

        const proxy = spawn('tinyproxy', ['-d', '-c', confPath]);
        const timeout = setTimeout(() => {
            state.tinyproxy.running = true;
            resolve();
        }, 5000);

        proxy.stdout.on('data', data => {
            const line = data.toString().trim();
            console.log(`[TINYPROXY] ${line}`);
            if (line.includes('Listening')) {
                clearTimeout(timeout);
                state.tinyproxy.running = true;
                log('Tinyproxy started');
                resolve();
            }
        });

        proxy.stderr.on('data', data => console.log(`[TINYPROXY] ${data.toString().trim()}`));
        proxy.on('close', code => {
            state.tinyproxy.running = false;
            log(`Tinyproxy exited: ${code}`);
        });
    });
}

// OpenVPN setup
async function setupOpenVPN() {
    const ovpnPath = '/app/portmap.ovpn';
    const useBuiltIn = !fs.existsSync(ovpnPath);
    const configPath = useBuiltIn ? '/app/app.ovpn' : ovpnPath;

    if (useBuiltIn) {
        log('No /app/portmap.ovpn found → using built-in app.ovpn');
    } else {
        log('Found /app/portmap.ovpn → using it');
    }

    return new Promise((resolve) => {
        log('Starting OpenVPN...');
        const vpn = spawn('sudo', ['openvpn', '--config', configPath, '--verb', '3']);

        vpn.stdout.on('data', data => {
            const line = data.toString();
            console.log(`[OPENVPN] ${line.trim()}`);
            if (line.includes('Initialization Sequence Completed')) {
                state.openvpn.connected = true;
                log('OpenVPN connected');
                parsePublicProxy(configPath);
                resolve();
            }
        });

        vpn.stderr.on('data', data => console.error(`[OPENVPN ERR] ${data.toString().trim()}`));
        vpn.on('close', code => {
            state.openvpn.running = false;
            log(`OpenVPN exited: ${code}`);
        });

        state.openvpn.running = true;

        setTimeout(() => {
            if (!state.openvpn.connected) {
                log('OpenVPN timeout → continue without public IP');
                state.openvpn.connected = true;
                resolve();
            }
        }, 45000);
    });
}

function parsePublicProxy(configPath) {
    try {
        const content = fs.readFileSync(configPath, 'utf8');
        const match = content.match(/remote\s+([^\s]+)\s+(\d+)/);
        if (match) {
            state.publicProxy = {
                type: 'http',
                host: match[1],
                port: parseInt(match[2]),
                user: 'free',
                pass: 'free'
            };
            log(`Public proxy: ${state.publicProxy.host}:${state.publicProxy.port}`);
        }
    } catch (e) {
        log(`Parse error: ${e.message}`);
    }
}

// Keepalive
async function keepalive() {
    try {
        const agent = new SocksProxyAgent('socks5://127.0.0.1:9050');
        await axios.get(`http://localhost:${PORT}/health`, { httpAgent: agent, timeout: 8000 });
    } catch (e) {
        log(`Keepalive failed: ${e.message}`);
    }
}

// Routes
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', services: state });
});

app.get('/info', (req, res) => {
    res.json(state.publicProxy || { local: `http://localhost:${PROXY_PORT}` });
});

app.get('/', (req, res) => {
    const info = state.publicProxy || { host: 'localhost', port: PROXY_PORT, user: 'free', pass: 'free' };
    res.send(`<!DOCTYPE html>
<html><head><title>Tor Proxy</title><style>body{font-family:Arial;background:#1e3c72;color:#fff;padding:40px;text-align:center;}</style></head>
<body><div style="background:rgba(255,255,255,0.1);padding:30px;border-radius:15px;max-width:500px;margin:auto;">
<h1>Free Tor HTTP Proxy</h1>
<p><strong>Host:</strong> ${info.host}<br><strong>Port:</strong> ${info.port}<br><strong>User:</strong> ${info.user}<br><strong>Pass:</strong> ${info.pass}</p>
<p style="color:#a0f7a0;">All traffic via Tor</p>
<p style="color:#ff9800;font-size:0.9em;">Ethical use only</p>
</div></body></html>`);
});

// Start
async function main() {
    log('=== Starting Tor Proxy Service ===');
    await setupTor();
    await setupTinyproxy();
    await setupOpenVPN();

    app.listen(PORT, () => {
        log(`Web UI: http://0.0.0.0:${PORT}`);
        log(`Proxy: http://0.0.0.0:${PROXY_PORT}`);
        log('=== All services ready ===');
    });

    setInterval(keepalive, 5 * 60 * 1000);
}

main().catch(err => {
    log(`FATAL: ${err.message}`);
    process.exit(1);
});
EOF

# === Create entrypoint.sh ===
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "==================================="
echo "Tor to HTTP Proxy Container Starting"
echo "==================================="

if [ -f "/app/portmap.ovpn" ]; then
    echo "Found /app/portmap.ovpn"
else
    echo "No /app/portmap.ovpn → using built-in config"
fi

exec node /app/app.js
EOF

RUN chmod +x /app/entrypoint.sh

# Expose ports
EXPOSE 3000 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Environment
ENV NODE_ENV=production

# Use non-root user
USER proxyuser

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
