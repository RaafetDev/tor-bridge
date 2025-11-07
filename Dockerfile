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

# Create TUN device directory and setup
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 2>/dev/null || true && \
    chmod 666 /dev/net/tun 2>/dev/null || true

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

# === app.js – Enhanced with better TUN handling ===
RUN cat > /app/app.js << 'EOF'
const express = require('express');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');

const app = express();
const PORT = process.env.PORT || 3000;
const PROXY_PORT = 8888;

let state = { tor: false, tinyproxy: false, openvpn: false, publicProxy: null };
function log(m) { console.log(`[${new Date().toISOString()}] ${m}`); }

// Ensure TUN device exists
function ensureTunDevice() {
    try {
        if (!fs.existsSync('/dev/net')) {
            execSync('sudo mkdir -p /dev/net', { stdio: 'inherit' });
        }
        if (!fs.existsSync('/dev/net/tun')) {
            execSync('sudo mknod /dev/net/tun c 10 200', { stdio: 'inherit' });
            execSync('sudo chmod 666 /dev/net/tun', { stdio: 'inherit' });
        }
        log('TUN device ready');
    } catch (e) {
        log(`TUN setup warning: ${e.message}`);
    }
}

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

// OpenVPN with TUN device check
async function setupOpenVPN() {
    ensureTunDevice();
    
    const ovpnPath = '/app/portmap.ovpn';
    const useBuiltIn = !fs.existsSync(ovpnPath);
    const configPath = useBuiltIn ? '/app/app.ovpn' : ovpnPath;
    log(useBuiltIn ? 'Using built-in OVPN' : 'Using mounted OVPN');

    return new Promise((res) => {
        const vpn = spawn('sudo', [
            'openvpn',
            '--config', configPath,
            '--dev-type', 'tun',
            '--dev', 'tun0',
            '--script-security', '2',
            '--verb', '3'
        ]);
        const t = setTimeout(() => { log('OVPN timeout – continuing without VPN'); res(); }, 45000);

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
        vpn.on('close', code => { 
            log(`OpenVPN exited: ${code}`); 
            if (code !== 0) state.openvpn = false;
            res(); 
        });
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
    const vpnStatus = state.openvpn ? '✓ VPN Connected' : '✗ VPN Unavailable (Tor only)';
    res.send(`<!DOCTYPE html><html><head><title>Tor Proxy</title><style>body{font-family:Arial;background:#1e3c72;color:#fff;padding:40px;text-align:center;}.status{color:#a0f7a0;}.warn{color:#f7a0a0;}</style></head><body><div style="background:rgba(255,255,255,0.1);padding:30px;border-radius:15px;max-width:500px;margin:auto;"><h1>🧅 Tor HTTP Proxy</h1><p><strong>Host:</strong> ${p.host}<br><strong>Port:</strong> ${p.port}<br><strong>User:</strong> free<br><strong>Pass:</strong> free</p><p class="${state.openvpn ? 'status' : 'warn'}">${vpnStatus}</p><p class="status">✓ Tor Network Active</p></div></body></html>`);
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
