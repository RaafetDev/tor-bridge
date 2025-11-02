# tor-bridge-render.com - SOLID ONION BRIDGE v2.2
# FULL STANDALONE DOCKERFILE | Render.com Free Tier
# MINIMAL: tor + curl | NO ca-certificates | NO chown | NO mkdir
# TORRC GENERATED AT RUNTIME IN APP DIR → ./torconfig
# FAST BOOTSTRAP | http-proxy | ESM | CRON | HEALTHCHECK

FROM node:20-slim

# === MINIMAL SYSTEM: tor + curl ONLY ===
RUN apt-get update && \
    apt-get install -y tor curl && \
    rm -rf /var/lib/apt/lists/*

# === SWITCH TO debian-tor USER ===
USER debian-tor
WORKDIR /home/debian-tor/app

# === package.json (ESM + DEPENDENCIES) ===
RUN echo '{ \
  "name": "solid-tor-onion-bridge", \
  "version": "2.2.0", \
  "main": "app.js", \
  "type": "module", \
  "scripts": { \
    "start": "node app.js" \
  }, \
  "dependencies": { \
    "http-proxy": "^1.18.1", \
    "http-proxy-agent": "^7.0.2" \
  } \
}' > package.json

# === INSTALL NODE DEPENDENCIES ===
RUN npm install --production

# === app.js → FAST BOOTSTRAP + RUNTIME torconfig ===
RUN echo "import { createServer } from 'http';\n\
import httpProxy from 'http-proxy';\n\
import { HttpsProxyAgent } from 'http-proxy-agent';\n\
import { spawn } from 'child_process';\n\
import { writeFileSync } from 'fs';\n\
import { resolve } from 'path';\n\
\n\
// === CONFIG ===\n\
const ONION_TARGET = 'https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/';\n\
const PORT = process.env.PORT || 10000;\n\
const SOCKS = 'socks5://127.0.0.1:9050';\n\
const TORRC_PATH = resolve(process.cwd(), 'torconfig');\n\
\n\
let tor, proxy, agent;\n\
\n\
// === RUNTIME TORRC GENERATION (FAST) ===\n\
function generateTorrc() {\n\
  const torrc = [\n\
    'SocksPort 9050',\n\
    'Log notice stdout',\n\
    'DataDirectory ./tor-data',\n\
    'RunAsDaemon 0',\n\
    'ControlPort 9051',\n\
    'CookieAuthentication 1'\n\
  ].join('\\n');\n\
  writeFileSync(TORRC_PATH, torrc);\n\
  console.log('[TORRC] Generated at:', TORRC_PATH);\n\
}\n\
\n\
// === TOR LAUNCH & FAST BOOTSTRAP ===\n\
async function startTor() {\n\
  return new Promise((resolve, reject) => {\n\
    generateTorrc();\n\
    tor = spawn('tor', ['-f', TORRC_PATH]);\n\
    tor.on('error', reject);\n\
    tor.on('close', code => code !== 0 && reject(new Error(`Tor exited: ${code}`)));\n\
    resolve();\n\
  });\n\
}\n\
\n\
async function waitForBootstrap() {\n\
  return new Promise((resolve, reject) => {\n\
    const seen = new Set();\n\
    const timeout = setTimeout(() => reject(new Error('Tor bootstrap timeout')), 90000);\n\
\n\
    const check = data => {\n\
      const line = data.toString();\n\
      const match = line.match(/Bootstrapped\\s+(\\d+)%/);\n\
      if (match) {\n\
        const pct = parseInt(match[1], 10);\n\
        if (!seen.has(pct)) {\n\
          seen.add(pct);\n\
          console.log(`[TOR] Bootstrapped: ${pct}%`);\n\
        }\n\
        if (pct === 100) {\n\
          clearTimeout(timeout);\n\
          resolve();\n\
        }\n\
      }\n\
    };\n\
\n\
    tor.stdout.on('data', check);\n\
    tor.stderr.on('data', check);\n\
  });\n\
}\n\
\n\
// === PROXY ENGINE (http-proxy) ===\n\
function createProxy() {\n\
  agent = new HttpsProxyAgent(SOCKS);\n\
  proxy = httpProxy.createProxyServer({\n\
    target: ONION_TARGET,\n\
    agent,\n\
    changeOrigin: true,\n\
    autoRewrite: true,\n\
    protocolRewrite: 'https',\n\
    secure: false,\n\
    followRedirects: true\n\
  });\n\
\n\
  proxy.on('error', (err, req, res) => {\n\
    console.error('[PROXY ERROR]', err.message);\n\
    if (!res.headersSent) {\n\
      res.writeHead(502, { 'Content-Type': 'text/plain' });\n\
      res.end('Tor Bridge Down');\n\
    }\n\
  });\n\
}\n\
\n\
// === CRON PING (KEEP ALIVE) ===\n\
function startCronPing() {\n\
  const ping = () => {\n\
    fetch(`http://localhost:${PORT}/health`, { signal: AbortSignal.timeout(5000) })\n\
      .then(() => console.log('[CRON] Health OK'))\n\
      .catch(() => {});\n\
  };\n\
  setInterval(ping, 4 * 60 * 1000);\n\
  setTimeout(ping, 15000);\n\
}\n\
\n\
// === HEALTH SERVER ===\n\
function startServer() {\n\
  const server = createServer((req, res) => {\n\
    if (req.url === '/health') {\n\
      res.writeHead(200, { 'Content-Type': 'text/plain' });\n\
      return res.end('OK');\n\
    }\n\
    proxy.web(req, res);\n\
  });\n\
\n\
  server.listen(PORT, () => {\n\
    console.log('================================');\n\
    console.log('SOLID TOR BRIDGE v2.2 LIVE');\n\
    console.log(`Port: ${PORT}`);\n\
    console.log(`SOCKS: 127.0.0.1:9050`);\n\
    console.log(`Target: ${ONION_TARGET}`);\n\
    console.log('================================');\n\
  });\n\
}\n\
\n\
// === MAIN ===\n\
(async () => {\n\
  try {\n\
    await startTor();\n\
    await waitForBootstrap();\n\
    createProxy();\n\
    startCronPing();\n\
    startServer();\n\
  } catch (err) {\n\
    console.error('==>[FATAL]<==', err.message);\n\
    process.exit(1);\n\
  }\n\
})();\n\
\n\
process.on('SIGTERM', () => {\n\
  tor?.kill();\n\
  proxy?.close();\n\
});\n\
" > app.js

# === EXPOSE + HEALTHCHECK ===
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
  CMD curl -f http://localhost:10000/health || exit 1

# === START ===
CMD ["npm", "start"]
