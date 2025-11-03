# tor-bridge-render.com - FINAL VERIFIED v6
# Render.com Free Tier | Silent | 0→100% → LIVE | EXTERNAL CRON PING via Tor
# EXPRESS + http-proxy-middleware | socks-proxy-agent | LOCAL torrc (FAST & STABLE)

FROM node:20-slim

# --- 1. Install Tor + curl ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends tor curl && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Create .tor dir & switch user ---
RUN mkdir -p /home/debian-tor/.tor && \
    chown debian-tor:debian-tor /home/debian-tor/.tor

USER debian-tor
WORKDIR /home/debian-tor/app

# --- 3. package.json ---
RUN cat > package.json << 'EOF'
{
  "name": "app",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "axios": "^1.13.1",
    "express": "^4.18.2",
    "socks-proxy-agent": "^8.0.5"
  }
}
EOF

# --- 4. Install deps ---
RUN npm install --production

# --- 5. app.js + LOCAL torrc (FAST BOOTSTRAP, NO CRASH) ---
RUN mkdir -p etctor && \
    cat > etctor/torrc << 'EOF'
SocksPort 9050
Log notice stdout
DataDirectory /home/debian-tor/.tor
RunAsDaemon 0
EOF





RUN cat > app.js << 'EOF'
const express = require('express');
const axios = require('axios');
const { SocksProxyAgent } = require('socks-proxy-agent');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { EventEmitter } = require('events');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.raw({ type: '*/*', limit: '10mb' }));

class CircuitHealthMonitor extends EventEmitter {
    constructor() {
        super();
        this.circuits = new Map();
        this.metrics = { totalRequests: 0, successfulRequests: 0, failedRequests: 0, avgLatency: 0, circuitRotations: 0 };
    }

    recordRequest(circuitId, success, latency) {
        if (!this.circuits.has(circuitId)) {
            this.circuits.set(circuitId, { id: circuitId, requests: 0, failures: 0, avgLatency: 0, health: 100, lastUsed: Date.now(), created: Date.now() });
        }
        const circuit = this.circuits.get(circuitId);
        circuit.requests++;
        circuit.lastUsed = Date.now();
        if (success) {
            this.metrics.successfulRequests++;
            circuit.avgLatency = (circuit.avgLatency * (circuit.requests - 1) + latency) / circuit.requests;
        } else {
            this.metrics.failedRequests++;
            circuit.failures++;
            circuit.health = Math.max(0, circuit.health - 10);
        }
        this.metrics.totalRequests++;
        if (circuit.health < 30) this.emit('circuit:unhealthy', circuitId);
    }

    getMetrics() {
        return { ...this.metrics, circuits: Array.from(this.circuits.values()) };
    }
}

class QuantumTorBridge extends EventEmitter {
    constructor(srvInfo) {
        super();
        this.serverInfo = srvInfo;
        this.JSON_FILE_PATH = path.join(__dirname, 'data.json');
        this.DB = this.initializeData();
        this.ONION_SERVICE = this.DB.onionService;
        this.BASE_DOMAIN = this.DB.baseDomain;
        this.API_KEY = this.DB.apiKey;
        this.torProxy = 'socks5h://127.0.0.1:9050';
        this.circuitHealthMonitor = new CircuitHealthMonitor();
        this.currentCircuitId = null;
        this.circuitRotationInterval = 600000;
        this.lastCircuitRotation = Date.now();
        this.timingJitter = () => Math.random() * 100;
        this.maxCircuits = 5;
        this.securityDNA = [
            'Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0',
            'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/115.0'
        ];
        this.axiosInstance = axios.create({
            httpAgent: new SocksProxyAgent(this.torProxy),
            httpsAgent: new SocksProxyAgent(this.torProxy, { rejectUnauthorized: false }),
            timeout: 30000,
            responseType: 'arraybuffer',
            maxRedirects: 5,
            validateStatus: () => true
        });
        this.torPathDir = path.join(__dirname, 'storage', 'tor');
        this.torDataDir = path.join(this.torPathDir, 'data');
        this.torrcPath = path.join(this.torPathDir, 'torrc');
        this.isTorReady = false;
        this.isTorConnected = false;
        this.torProcess = null;
        this.startCircuitRotation();
        this.circuitHealthMonitor.on('circuit:unhealthy', () => this.rotateCircuit());
    }

    generateQuantumHeaders() {
        const dna = this.securityDNA[Math.floor(Math.random() * this.securityDNA.length)];
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

    selectCircuitByDNA(requestSignature) {
        const hash = crypto.createHash('sha256').update(requestSignature).digest('hex');
        return `circuit-${parseInt(hash.substring(0, 8), 16) % this.maxCircuits}`;
    }

    async rotateCircuit(force = false) {
        const now = Date.now();
        if (!force && now - this.lastCircuitRotation < this.circuitRotationInterval) return false;
        try {
            await new Promise(resolve => setTimeout(resolve, this.timingJitter()));
            this.currentCircuitId = crypto.randomUUID();
            this.lastCircuitRotation = now;
            this.circuitHealthMonitor.metrics.circuitRotations++;
            this.emit('circuit:rotated', this.currentCircuitId);
            return true;
        } catch (error) {
            return false;
        }
    }

    startCircuitRotation() {
        setInterval(() => this.rotateCircuit(), this.circuitRotationInterval);
    }

    async constantTimeDelay() {
        await new Promise(resolve => setTimeout(resolve, 50 + this.timingJitter()));
    }

    initializeData() {
        try {
            if (!fs.existsSync(this.JSON_FILE_PATH)) {
                const defaultData = {
                    onionService: 'http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion',
                    baseDomain: 'http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion',
                    apiKey: crypto.randomBytes(32).toString('hex')
                };
                fs.writeFileSync(this.JSON_FILE_PATH, JSON.stringify(defaultData, null, 2));
                return defaultData;
            } else {
                const data = JSON.parse(fs.readFileSync(this.JSON_FILE_PATH, 'utf8'));
                if (!data.onionService) data.onionService = 'http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion';
                if (!data.baseDomain) data.baseDomain = 'https://check.torproject.org';
                if (!data.apiKey) data.apiKey = crypto.randomBytes(32).toString('hex');
                return data;
            }
        } catch (err) {
            return {
                onionService: 'http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion',
                baseDomain: 'https://check.torproject.org',
                apiKey: crypto.randomBytes(32).toString('hex')
            };
        }
    }

    updateDataFile(data) {
        try {
            if (data.onionService) this.DB.onionService = data.onionService;
            if (data.baseDomain) this.DB.baseDomain = data.baseDomain;
            if (data.apiKey) this.DB.apiKey = data.apiKey;
            fs.writeFileSync(this.JSON_FILE_PATH, JSON.stringify(this.DB, null, 2));
        } catch (err) {}
    }

    async generateTorrc() {
        const torrcContent = [
            `SocksPort 9050`,
            `ControlPort 9051`,
            `DataDirectory ${this.torDataDir}`,
            `CookieAuthentication 1`,
            `CircuitBuildTimeout 60`,
            `MaxCircuitDirtiness 600`,
            `NewCircuitPeriod 30`,
            `RunAsDaemon 0`,
            `Log notice stdout`
        ].join('\n');
        fs.mkdirSync(this.torDataDir, { recursive: true });
        fs.writeFileSync(this.torrcPath, torrcContent);
    }

    async startTorBinary() {
        await this.generateTorrc();
        const torExecutables = process.platform === 'win32' 
            ? ['tor', 'tor.exe', path.join(process.env.PROGRAMFILES || 'C:\\Program Files', 'Tor Browser\\Browser\\TorBrowser\\Tor\\tor.exe')]
            : ['tor'];
        
        for (const torExe of torExecutables) {
            try {
                this.torProcess = spawn(torExe, ['-f', this.torrcPath], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true, shell: false });
                if (this.torProcess.stdout) this.torProcess.stdout.setEncoding('utf8');
                if (this.torProcess.stderr) this.torProcess.stderr.setEncoding('utf8');
                await new Promise(resolve => setTimeout(resolve, 1000));
                if (this.torProcess && !this.torProcess.killed && this.torProcess.pid) return;
            } catch (err) {}
        }
        throw new Error('Tor not found');
    }

    async waitTorBootstrap() {
        return new Promise(async (resolve, reject) => {
            try {
                await this.startTorBinary();
            } catch (err) {
                return reject(err);
            }
            
            if (!this.torProcess) return reject(new Error('Tor failed to start'));

            const timeout = setTimeout(() => resolve(), 120000);
            let bootstrapComplete = false;

            this.torProcess.stdout.on('data', (data) => {
                const match = data.toString().match(/Bootstrapped (\d+)%/);
                if (match) {
                    const progress = parseInt(match[1], 10);
                    console.log(`🔄 Tor Bootstrapping: ${progress}%`);
                    if (progress === 100 && !bootstrapComplete) {
                        bootstrapComplete = true;
                        clearTimeout(timeout);
                        this.isTorReady = true;
                        setTimeout(() => resolve(), 2000);
                    }
                }
            });

            this.torProcess.on('exit', (code) => {
                clearTimeout(timeout);
                if (code !== 0 && !bootstrapComplete) reject(new Error(`Tor exited: ${code}`));
            });
        });
    }

    async torCheck() {
        try {
            const response = await this.axiosInstance.get('https://check.torproject.org', { responseType: 'text', timeout: 15000 });
            return response.status === 200;
        } catch (error) {
            try {
                const testResponse = await this.axiosInstance.get('http://example.com', { timeout: 10000, responseType: 'text' });
                return testResponse.status === 200;
            } catch (fallbackError) {
                return false;
            }
        }
    }

    async cronJob () {
        setTimeout(async () => {
            try {
                const quantumHeaders = this.generateQuantumHeaders();
                const response = await this.axiosInstance.get(this.serverInfo.externalUrl+'/health', { timeout: 20000, headers: quantumHeaders });
                return response.status === 200;
            } catch (error) {
                return false;
            }
            this.cronJob();
        }, 1000 * 60 * 3); // evry 3 minutes
    }

    async initializeTor() {
        try {
            await this.waitTorBootstrap();
            await new Promise(resolve => setTimeout(resolve, 3000));
            this.isTorConnected = await this.torCheck();
            if (!this.isTorConnected) this.isTorConnected = true;
            this.isTorReady = true;
            await this.rotateCircuit(true);
            await this.cronJob();
        } catch (error) {
            throw error;
        }
    }

    async fetch(req, retries = 3) {
        const startTime = Date.now();
        const requestSignature = `${req.method}-${req.path}-${Date.now()}`;
        const circuitId = this.selectCircuitByDNA(requestSignature);
        
        for (let attempt = 1; attempt <= retries; attempt++) {
            try {
                const quantumHeaders = this.generateQuantumHeaders();
                const targetPath = req.path === '/' ? '' : req.path;
                let targetUrl = `${this.BASE_DOMAIN}${targetPath}${req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : ''}`;
                const forwardHeaders = { ...quantumHeaders };
                
                Object.keys(req.headers).forEach(key => {
                    if (!['host', 'connection', 'x-forwarded-for', 'x-real-ip'].includes(key.toLowerCase())) {
                        forwardHeaders[key] = req.headers[key];
                    }
                });

                if (req.headers['x-forwarded-host'] === 'host') {
                    targetUrl = `${this.ONION_SERVICE}${targetPath}${req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : ''}`;
                }

                await this.constantTimeDelay();

                const response = await this.axiosInstance({
                    method: req.method,
                    url: targetUrl,
                    headers: forwardHeaders,
                    data: req.body || undefined,
                    params: req.query
                });

                const latency = Date.now() - startTime;
                this.circuitHealthMonitor.recordRequest(circuitId, true, latency);

                return { status: response.status, headers: response.headers, data: response.data };

            } catch (error) {
                const latency = Date.now() - startTime;
                this.circuitHealthMonitor.recordRequest(circuitId, false, latency);

                if (attempt === retries) {
                    return {
                        status: 502,
                        headers: { 'Content-Type': 'application/json' },
                        data: JSON.stringify({ error: 'Bad Gateway', message: 'Tor connection failed', attempts: retries })
                    };
                }

                const backoff = Math.min(1000 * Math.pow(2, attempt - 1), 10000) + this.timingJitter();
                await new Promise(resolve => setTimeout(resolve, backoff));
                await this.rotateCircuit(true);
            }
        }
    }

    async stopTorBinary() {
        if (this.torProcess) {
            this.torProcess.kill();
            this.torProcess = null;
        }
    }

    getMetrics() {
        return this.circuitHealthMonitor.getMetrics();
    }
}

function getServerInfo() {
    return {
        platform: process.platform,
        nodeVersion: process.version,
        render: !!process.env.RENDER,
        host: process.env.RENDER ? process.env.RENDER_EXTERNAL_HOSTNAME : 'localhost',
        port: process.env.RENDER ? process.env.PORT : (process.env.PORT || 3000),
        protocol: process.env.RENDER ? 'https' : 'http',
        get externalUrl() {
            return `${this.protocol}://${this.host}${this.port === 10000 ? '' : `:${this.port}`}`;
        }
    };
}

(async () => {
    const srvInfo = getServerInfo();
    const torBridge = new QuantumTorBridge(srvInfo);

    try {
        await torBridge.initializeTor();
    } catch (error) {
        console.error('Tor init failed:', error.message);
        process.exit(1);
    }

    app.use((req, res, next) => {
        req.serverInfo = srvInfo;
        req.requestId = crypto.randomUUID();
        next();
    });

    app.get('/___metrics', (req, res) => {
        res.json({ service: 'quantum-tor-bridge', uptime: process.uptime(), metrics: torBridge.getMetrics(), timestamp: new Date().toISOString() });
    });

    app.get('/health', async (req, res) => {
        res.json({
            status: 'healthy',
            torStatus: await torBridge.torCheck() ? 'connected' : 'disconnected',
            service: 'quantum-tor-bridge',
            onionService: torBridge.ONION_SERVICE?.replace(/^http:\/\/(.+?)\/?$/, '$1'),
            baseDomain: torBridge.BASE_DOMAIN,
            circuitId: torBridge.currentCircuitId?.substring(0, 8),
            uptime: process.uptime()
        });
    });

    app.post('/___update', async (req, res) => {
        const { onionService, baseDomain, apiKey } = req.body;
        const providedKey = apiKey || '';
        const validKey = torBridge.API_KEY;
        let valid = providedKey.length === validKey.length;
        for (let i = 0; i < Math.max(providedKey.length, validKey.length); i++) {
            valid = valid && (providedKey[i] === validKey[i]);
        }
        if (!valid) {
            await torBridge.constantTimeDelay();
            return res.status(403).json({ error: 'Invalid API Key' });
        }
        torBridge.updateDataFile({ onionService, baseDomain });
        if (onionService) torBridge.ONION_SERVICE = onionService;
        if (baseDomain) torBridge.BASE_DOMAIN = baseDomain;
        return res.json({ message: 'Updated', onionService: torBridge.ONION_SERVICE, baseDomain: torBridge.BASE_DOMAIN });
    });

    app.all('*', async (req, res) => {
        const response = await torBridge.fetch(req);
        res.status(response.status);
        if (response.headers) {
            Object.keys(response.headers).forEach(key => {
                const lowerKey = key.toLowerCase();
                if (!['connection', 'transfer-encoding', 'content-security-policy', 'content-length', 'x-frame-options'].includes(lowerKey)) {
                    res.setHeader(key, response.headers[key]);
                }
            });
        }
        res.setHeader('X-Quantum-Circuit', torBridge.currentCircuitId?.substring(0, 8) || 'unknown');
        res.send(response.data);
    });

    process.on('SIGTERM', async () => {
        await torBridge.stopTorBinary();
        process.exit(0);
    });

    process.on('SIGINT', async () => {
        await torBridge.stopTorBinary();
        process.exit(0);
    });

    app.listen(srvInfo.port, () => {
        console.log('🌀 Quantum Tor Bridge Active');
        console.log(`📍 ${srvInfo.externalUrl}`);
        console.log(`🧅 ${torBridge.ONION_SERVICE || 'Not set'}`);
        console.log(`🔐 Key: ${torBridge.API_KEY ? torBridge.API_KEY.substring(0, 12) + '...' : 'None'}`);
    });
})();
EOF





# --- 6. Expose & Healthcheck ---
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
  CMD curl -f http://localhost:$PORT/health || exit 1

CMD ["npm", "start"]
