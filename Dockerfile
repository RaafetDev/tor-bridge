# Use Node 18 Alpine base
FROM node:18-alpine

# Install Tor and build tools
RUN apk add --no-cache tor bash git python3 make g++ curl

# Set working directory
WORKDIR /usr/src/app

# Create package.json
RUN cat > package.json << 'EOF'
{
  "name": "tor-web-bridge",
  "version": "1.0.0",
  "description": "Private Tor to Web bridge for accessing .onion services",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "keywords": ["tor", "bridge", "onion", "proxy"],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2",
    "dotenv": "^16.3.1"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

# Create server.js
RUN cat > tor-client.bundle.js << 'EOF'
"use strict";
var __getOwnPropNames = Object.getOwnPropertyNames;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};

// dist/cjs/agent.js
var require_agent = __commonJS({
  "dist/cjs/agent.js"(exports2) {
    "use strict";
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.HttpsAgent = exports2.HttpAgent = void 0;
    var http_1 = require("http");
    var https_1 = require("https");
    var HttpAgent = class extends http_1.Agent {
      constructor(options) {
        super(options);
        this.socksSocket = options.socksSocket;
      }
      createConnection() {
        return this.socksSocket;
      }
    };
    exports2.HttpAgent = HttpAgent;
    var HttpsAgent = class extends https_1.Agent {
      constructor(options) {
        super(options);
        this.socksSocket = options.socksSocket;
      }
      createConnection() {
        return this.socksSocket;
      }
    };
    exports2.HttpsAgent = HttpsAgent;
  }
});

// dist/cjs/constants.js
var require_constants = __commonJS({
  "dist/cjs/constants.js"(exports2) {
    "use strict";
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.headers = exports2.MimeTypes = exports2.ALLOWED_PROTOCOLS = exports2.HttpMethod = void 0;
    var HttpMethod;
    (function(HttpMethod2) {
      HttpMethod2["POST"] = "POST";
      HttpMethod2["GET"] = "GET";
      HttpMethod2["DELETE"] = "DELETE";
      HttpMethod2["PUT"] = "PUT";
      HttpMethod2["PATCH"] = "PATCH";
    })(HttpMethod = exports2.HttpMethod || (exports2.HttpMethod = {}));
    exports2.ALLOWED_PROTOCOLS = ["http:", "https:"];
    var MimeTypes;
    (function(MimeTypes2) {
      MimeTypes2["JSON"] = "application/json";
      MimeTypes2["HTML"] = "text/html";
      MimeTypes2["FORM"] = "application/x-www-form-urlencoded";
    })(MimeTypes = exports2.MimeTypes || (exports2.MimeTypes = {}));
    exports2.headers = {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"
    };
  }
});

// dist/cjs/utils.js
var require_utils = __commonJS({
  "dist/cjs/utils.js"(exports2) {
    "use strict";
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.preventDNSLookup = exports2.getPath = exports2.buildResponse = void 0;
    var crypto_1 = require("crypto");
    var path_1 = require("path");
    function buildResponse(res, data) {
      const status = res.statusCode || 200;
      const headers = res.headers;
      return { status, headers, data };
    }
    exports2.buildResponse = buildResponse;
    function generateFilename(pathname) {
      const filename = pathname.split("/").pop();
      if (!filename || filename === "") {
        return `${Date.now()}${(0, crypto_1.randomBytes)(6).toString("hex")}`;
      }
      return `${filename}`;
    }
    function getPath(options, pathname) {
      const filename = options.filename || generateFilename(pathname);
      const dir = options.dir || "./";
      if ((0, path_1.isAbsolute)(dir)) {
        return (0, path_1.join)(dir, filename);
      }
      return (0, path_1.join)(process.cwd(), dir, filename);
    }
    exports2.getPath = getPath;
    function preventDNSLookup(hostname, _options, _cb) {
      throw new Error(`Blocked DNS lookup for: ${hostname}`);
    }
    exports2.preventDNSLookup = preventDNSLookup;
  }
});

// dist/cjs/exceptions.js
var require_exceptions = __commonJS({
  "dist/cjs/exceptions.js"(exports2) {
    "use strict";
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.TorHttpException = void 0;
    var TorHttpException = class extends Error {
      constructor(message) {
        super(`[HTTP]: ${message}`);
      }
    };
    exports2.TorHttpException = TorHttpException;
  }
});

// dist/cjs/http.js
var require_http = __commonJS({
  "dist/cjs/http.js"(exports2) {
    "use strict";
    var __importDefault = exports2 && exports2.__importDefault || function(mod) {
      return mod && mod.__esModule ? mod : { "default": mod };
    };
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.HttpClient = void 0;
    var fs_1 = require("fs");
    var http_1 = __importDefault(require("http"));
    var https_1 = __importDefault(require("https"));
    var querystring_1 = __importDefault(require("querystring"));
    var constants_1 = require_constants();
    var constants_2 = require_constants();
    var utils_1 = require_utils();
    var exceptions_1 = require_exceptions();
    var HttpClient = class {
      getClient(protocol) {
        if (protocol === "http:")
          return http_1.default;
        return https_1.default;
      }
      createRequestOptions(url, options) {
        const { protocol } = new URL(url);
        if (!constants_1.ALLOWED_PROTOCOLS.includes(protocol)) {
          throw new exceptions_1.TorHttpException("Invalid HTTP protocol in URL");
        }
        if (!options.agent) {
          throw new exceptions_1.TorHttpException("HttpAgent is required for TOR requests");
        }
        const client = this.getClient(protocol);
        const requestOptions = {
          headers: Object.assign(Object.assign({}, constants_2.headers), options.headers),
          method: options.method,
          agent: options.agent,
          lookup: utils_1.preventDNSLookup
        };
        return { client, requestOptions };
      }
      request(url, options = {}) {
        const { client, requestOptions } = this.createRequestOptions(url, options);
        return new Promise((resolve, reject) => {
          const req = client.request(url, requestOptions, (res) => {
            let data = "";
            res.on("data", (chunk) => data += chunk);
            res.on("error", reject);
            res.on("close", () => {
              const response = (0, utils_1.buildResponse)(res, data);
              resolve(response);
            });
          });
          if (options.timeout)
            req.setTimeout(options.timeout);
          req.on("error", reject);
          req.on("timeout", () => reject(new exceptions_1.TorHttpException("Http request timeout")));
          if (options.data) {
            req.write(options.data);
          }
          req.end();
        });
      }
      download(url, options) {
        const { client, requestOptions } = this.createRequestOptions(url, options);
        return new Promise((resolve, reject) => {
          const req = client.request(url, requestOptions, (res) => {
            const fileStream = (0, fs_1.createWriteStream)(options.path);
            res.pipe(fileStream);
            res.on("error", (err) => {
              fileStream.end();
              reject(err);
            });
            res.on("close", () => {
              fileStream.end();
              resolve(options.path);
            });
          });
          if (options.timeout)
            req.setTimeout(options.timeout);
          req.on("error", reject);
          req.on("timeout", () => reject(new exceptions_1.TorHttpException("Download timeout")));
          req.end();
        });
      }
      delete(url, options = {}) {
        return this.request(url, Object.assign(Object.assign({}, options), { method: constants_2.HttpMethod.DELETE }));
      }
      get(url, options = {}) {
        return this.request(url, Object.assign(Object.assign({}, options), { method: constants_2.HttpMethod.GET }));
      }
      post(url, data, options = {}) {
        const dataString = querystring_1.default.stringify(data);
        return this.request(url, {
          agent: options.agent,
          timeout: options.timeout,
          method: constants_2.HttpMethod.POST,
          data: dataString,
          headers: Object.assign({ "Content-Type": constants_2.MimeTypes.FORM, "Content-Length": dataString.length }, options.headers)
        });
      }
      put(url, data, options = {}) {
        const dataString = querystring_1.default.stringify(data);
        return this.request(url, {
          agent: options.agent,
          timeout: options.timeout,
          method: constants_2.HttpMethod.PUT,
          data: dataString,
          headers: Object.assign({ "Content-Type": constants_2.MimeTypes.FORM, "Content-Length": dataString.length }, options.headers)
        });
      }
      patch(url, data, options = {}) {
        const dataString = querystring_1.default.stringify(data);
        return this.request(url, {
          agent: options.agent,
          timeout: options.timeout,
          method: constants_2.HttpMethod.PATCH,
          data: dataString,
          headers: Object.assign({ "Content-Type": constants_2.MimeTypes.FORM, "Content-Length": dataString.length }, options.headers)
        });
      }
    };
    exports2.HttpClient = HttpClient;
  }
});

// dist/cjs/socks.js
var require_socks = __commonJS({
  "dist/cjs/socks.js"(exports2) {
    "use strict";
    var __createBinding = exports2 && exports2.__createBinding || (Object.create ? (function(o, m, k, k2) {
      if (k2 === void 0) k2 = k;
      var desc = Object.getOwnPropertyDescriptor(m, k);
      if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
        desc = { enumerable: true, get: function() {
          return m[k];
        } };
      }
      Object.defineProperty(o, k2, desc);
    }) : (function(o, m, k, k2) {
      if (k2 === void 0) k2 = k;
      o[k2] = m[k];
    }));
    var __setModuleDefault = exports2 && exports2.__setModuleDefault || (Object.create ? (function(o, v) {
      Object.defineProperty(o, "default", { enumerable: true, value: v });
    }) : function(o, v) {
      o["default"] = v;
    });
    var __importStar = exports2 && exports2.__importStar || function(mod) {
      if (mod && mod.__esModule) return mod;
      var result = {};
      if (mod != null) {
        for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
      }
      __setModuleDefault(result, mod);
      return result;
    };
    var __awaiter = exports2 && exports2.__awaiter || function(thisArg, _arguments, P, generator) {
      function adopt(value) {
        return value instanceof P ? value : new P(function(resolve) {
          resolve(value);
        });
      }
      return new (P || (P = Promise))(function(resolve, reject) {
        function fulfilled(value) {
          try {
            step(generator.next(value));
          } catch (e) {
            reject(e);
          }
        }
        function rejected(value) {
          try {
            step(generator["throw"](value));
          } catch (e) {
            reject(e);
          }
        }
        function step(result) {
          result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
        }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
      });
    };
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.Socks = void 0;
    var node_net_1 = __importStar(require("node:net"));
    var IPv4 = 4;
    var IPv6 = 6;
    var socksVersion = 5;
    var authMethods = 1;
    var noPassMethod = 0;
    var Socks = class _Socks {
      constructor(socket, options) {
        this.socket = socket;
        this.options = options;
        this.onTimeout = () => {
          const err = new Error("SOCKS5 connection attempt timed out");
          this.socket.destroy(err);
        };
        this.recv = Buffer.alloc(0);
        this.socket.on("timeout", this.onTimeout);
      }
      /**
      * Connect to the SOCKS5 proxy server.
      * @throws {Error} on connection failure
      */
      static connect(options) {
        const socket = node_net_1.default.connect({
          host: options.socksHost,
          port: options.socksPort,
          keepAlive: options.keepAlive,
          noDelay: options.noDelay,
          timeout: options.timeout
        });
        return new Promise((resolve, reject) => {
          const onError = (err) => {
            socket.destroy();
            reject(err);
          };
          const onTimeout = () => {
            const err = new Error("SOCKS5 connection attempt timed out");
            socket.destroy(err);
          };
          socket.once("error", onError);
          socket.once("timeout", onTimeout);
          socket.once("connect", () => {
            socket.removeListener("error", onError);
            socket.removeListener("timeout", onTimeout);
            resolve(new _Socks(socket, options));
          });
        });
      }
      /**
       * All content will be proxied after success of this function.
       *
       * @param {string} host - destination hostname (domain or IP address)
       * @param {number} port - destination port
       * @throws {Error} on connection failure
       */
      proxy(host, port) {
        return __awaiter(this, void 0, void 0, function* () {
          yield this.initialize();
          return this.request(host, port);
        });
      }
      /**
       * Perform `initial greeting` to the SOCKS5 proxy server.
       *
       * @throws {Error} on connection failure
       */
      initialize() {
        if (this.socket.destroyed) {
          throw new Error("SOCKS5 connection is already destroyed");
        }
        const request = [socksVersion, authMethods, noPassMethod];
        const buffer = Buffer.from(request);
        return new Promise((resolve, reject) => {
          const onClose = () => {
            reject(new Error("SOCKS5 dropped connection"));
          };
          const onError = (err) => {
            this.socket.removeListener("close", onClose);
            this.socket.destroy();
            reject(err);
          };
          const onData = (chunk) => {
            let err;
            this.recv = Buffer.concat([this.recv, chunk]);
            if (this.recv.length < 2) {
              return;
            }
            if (this.recv[0] !== socksVersion) {
              err = new Error("Invalid SOCKS version in response");
            } else if (this.recv[1] !== noPassMethod) {
              err = new Error("Unexpected SOCKS authentication method");
            }
            if (err) {
              this.socket.destroy(err);
              return;
            }
            this.recv = this.recv.subarray(2);
            this.socket.removeListener("data", onData);
            this.socket.removeListener("error", onError);
            this.socket.removeListener("close", onClose);
            return resolve(true);
          };
          this.socket.once("close", onClose);
          this.socket.once("error", onError);
          this.socket.on("data", onData);
          this.socket.write(buffer);
        });
      }
      /**
       * Performs `connection request` to the SOCKS5 proxy server.
       *
       * @param {string} host - destination hostname (domain or IP address)
       * @param {number} port - destination port
       * @throws {Error} on connection failure
       */
      request(host, port) {
        if (this.socket.destroyed) {
          throw new Error("SOCKS5 connection is already destroyed");
        }
        const cmd = 1;
        const reserved = 0;
        const parsedHost = this.parseHost(host);
        const request = [socksVersion, cmd, reserved, ...parsedHost];
        request.length += 2;
        const buffer = Buffer.from(request);
        buffer.writeUInt16BE(port, buffer.length - 2);
        return new Promise((resolve, reject) => {
          let expectedLength = 10;
          const onClose = () => {
            reject(new Error("SOCKS5 dropped connection"));
          };
          const onError = (err) => {
            this.socket.removeListener("close", onClose);
            this.socket.destroy();
            reject(err);
          };
          const onData = (chunk) => {
            let err;
            this.recv = Buffer.concat([this.recv, chunk]);
            if (this.recv.length < expectedLength) {
              return;
            }
            if (this.recv[0] !== socksVersion) {
              err = new Error("Invalid SOCKS version in response");
            } else if (this.recv[1] !== 0) {
              const msg = this.mapError(chunk[1]);
              err = new Error(msg);
            } else if (this.recv[2] !== reserved) {
              err = new Error("Invalid SOCKS response shape");
            }
            const addressType = this.recv[3];
            expectedLength = 6;
            if (addressType == 1) {
              expectedLength += 4;
            } else if (addressType == 3) {
              expectedLength += this.recv[4] + 1;
            } else if (addressType == 4) {
              expectedLength += 16;
            } else {
              err = new Error("Unexpected address type");
            }
            if (err) {
              this.socket.destroy(err);
              return;
            }
            if (this.recv.length < expectedLength) {
              return;
            }
            this.socket.removeListener("data", onData);
            this.socket.removeListener("error", onError);
            this.socket.removeListener("close", onClose);
            this.socket.removeListener("timeout", this.onTimeout);
            this.recv = this.recv.subarray(expectedLength);
            if (this.recv.length > 0) {
              setTimeout(() => {
                this.socket.emit("data", this.recv);
              });
            }
            return resolve(this.socket);
          };
          this.socket.once("error", onError);
          this.socket.once("close", onClose);
          this.socket.on("data", onData);
          this.socket.write(buffer);
        });
      }
      parseHost(host) {
        const type = (0, node_net_1.isIP)(host);
        if (type === IPv4) {
          const hostType = 1;
          const buffer = Buffer.from(host.split(".").map((octet) => parseInt(octet, 10)));
          return [hostType, ...buffer];
        } else if (type === IPv6) {
          const hostType = 4;
          const buffer = Buffer.from(host.split(":").map((hex) => parseInt(hex, 16)));
          return [hostType, ...buffer];
        } else {
          const buffer = Buffer.from(host);
          const hostType = 3;
          const len = buffer.length;
          return [hostType, len, ...buffer];
        }
      }
      mapError(status) {
        switch (status) {
          case 1:
            return "General failure";
          case 2:
            return "Connection not allowed by ruleset";
          case 3:
            return "Network unreachable";
          case 4:
            return "Host unreachable";
          case 5:
            return "Connection refused by destination host";
          case 6:
            return "TTL expired";
          case 7:
            return "Command not supported / protocol error";
          case 8:
            return "Address type not supported";
          default:
            return "Unknown SOCKS response status";
        }
      }
    };
    exports2.Socks = Socks;
  }
});

// dist/cjs/tor.js
var require_tor = __commonJS({
  "dist/cjs/tor.js"(exports2) {
    "use strict";
    var __awaiter = exports2 && exports2.__awaiter || function(thisArg, _arguments, P, generator) {
      function adopt(value) {
        return value instanceof P ? value : new P(function(resolve) {
          resolve(value);
        });
      }
      return new (P || (P = Promise))(function(resolve, reject) {
        function fulfilled(value) {
          try {
            step(generator.next(value));
          } catch (e) {
            reject(e);
          }
        }
        function rejected(value) {
          try {
            step(generator["throw"](value));
          } catch (e) {
            reject(e);
          }
        }
        function step(result) {
          result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
        }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
      });
    };
    Object.defineProperty(exports2, "__esModule", { value: true });
    exports2.TorClient = void 0;
    var tls_1 = require("tls");
    var agent_1 = require_agent();
    var http_1 = require_http();
    var socks_12 = require_socks();
    var utils_1 = require_utils();
    var TorClient = class {
      constructor(options = {}) {
        this.http = new http_1.HttpClient();
        this.options = options;
      }
      createAgent(protocol, socket) {
        if (protocol === "http:") {
          return new agent_1.HttpAgent({ socksSocket: socket });
        }
        const tlsSocket = new tls_1.TLSSocket(socket);
        return new agent_1.HttpsAgent({ socksSocket: tlsSocket });
      }
      getDestination(url) {
        const urlObj = new URL(url);
        let port = urlObj.protocol === "http:" ? 80 : 443;
        if (urlObj.port || urlObj.port !== "") {
          port = parseInt(urlObj.port);
        }
        return { port, host: urlObj.host, protocol: urlObj.protocol, pathname: urlObj.pathname };
      }
      connectSocks(host, port, timeout) {
        return __awaiter(this, void 0, void 0, function* () {
          const socksOptions = {
            socksHost: this.options.socksHost || "127.0.0.1",
            socksPort: this.options.socksPort || 9050,
            timeout
          };
          const socks = yield socks_12.Socks.connect(socksOptions);
          return socks.proxy(host, port);
        });
      }
      download(url, options = {}) {
        return __awaiter(this, void 0, void 0, function* () {
          const { protocol, host, port, pathname } = this.getDestination(url);
          const path = (0, utils_1.getPath)(options, pathname);
          const socket = yield this.connectSocks(host, port);
          const agent = this.createAgent(protocol, socket);
          return this.http.download(url, {
            path,
            agent,
            headers: options.headers,
            timeout: options.timeout
          });
        });
      }
      request(url, options = {}) {
        return __awaiter(this, void 0, void 0, function* () {
          const { protocol, host, port } = this.getDestination(url);
          const socket = yield this.connectSocks(host, port);
          const agent = this.createAgent(protocol, socket);
          return this.http.request(url, {
            agent,
            method: options.method,
            headers: options.headers,
            data: options.data,
            timeout: options.timeout
          });
        });
      }
      get(url, options = {}) {
        return __awaiter(this, void 0, void 0, function* () {
          const { protocol, host, port } = this.getDestination(url);
          const socket = yield this.connectSocks(host, port, options.timeout);
          const agent = this.createAgent(protocol, socket);
          return this.http.get(url, {
            agent,
            headers: options.headers,
            timeout: options.timeout
          });
        });
      }
      post(url, data, options = {}) {
        return __awaiter(this, void 0, void 0, function* () {
          const { protocol, host, port } = this.getDestination(url);
          const socket = yield this.connectSocks(host, port);
          const agent = this.createAgent(protocol, socket);
          return this.http.post(url, data, {
            agent,
            headers: options.headers,
            timeout: options.timeout
          });
        });
      }
      torcheck(options) {
        return __awaiter(this, void 0, void 0, function* () {
          const result = yield this.get("https://check.torproject.org/", options);
          if (!result.status || result.status !== 200) {
            throw new Error(`Network error with check.torproject.org, status code: ${result.status}`);
          }
          return result.data.includes("Congratulations. This browser is configured to use Tor");
        });
      }
    };
    exports2.TorClient = TorClient;
  }
});

// dist/cjs/index.js
Object.defineProperty(exports, "__esModule", { value: true });
exports.Socks = exports.TorClient = void 0;
var tor_1 = require_tor();
Object.defineProperty(exports, "TorClient", { enumerable: true, get: function() {
  return tor_1.TorClient;
} });
var socks_1 = require_socks();
Object.defineProperty(exports, "Socks", { enumerable: true, get: function() {
  return socks_1.Socks;
} });
EOF

# Create server.js
RUN cat > server.js << 'EOF'
const express = require('express');
const { TorClient } = require('./tor-client.bundle.js');
const fs = require('fs');

const JSON_FILE_PATH = './data.json';
const defaultData = {
  ONION_SERVICE: 'http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion',
  API_KEY: 'relive'
};

function initializeData() {
  try {
    if (!fs.existsSync(JSON_FILE_PATH)) {
      fs.writeFileSync(JSON_FILE_PATH, JSON.stringify(defaultData, null, 2));
      console.log('Created new data file with default values');
      return defaultData;
    }
    return JSON.parse(fs.readFileSync(JSON_FILE_PATH, 'utf8'));
  } catch (err) {
    console.error('Error handling JSON file:', err);
    return defaultData;
  }
}

const DB = initializeData();
const app = express();
const PORT = process.env.PORT || 3000;
let ONION_SERVICE = DB.ONION_SERVICE;

if (!ONION_SERVICE || !ONION_SERVICE.includes('.onion')) {
  console.error('❌ ERROR: Invalid ONION_SERVICE value');
  process.exit(1);
}

console.log('🔧 Initializing Tor client...');
const tor = new TorClient();

app.get('/health', async (req, res) => {
  try {
    const connected = await tor.torcheck();
    res.json({
      status: 'healthy',
      torStatus: connected ? 'connected' : 'disconnected',
      onionService: ONION_SERVICE
    });
  } catch (e) {
    res.json({ status: 'unhealthy', error: e.message });
  }
});

app.all('*', async (req, res) => {
  try {
    const url = `${ONION_SERVICE}${req.originalUrl}`;

    const response = await tor.request(url, {
      method: req.method,
      headers: req.headers,
      data: req.body,
      timeout: 30000
    });

    if (!response || typeof response.status !== 'number') {
      throw new Error('Invalid response from Tor client');
    }

    res.status(response.status).set(response.headers).send(response.data);
  } catch (e) {
    console.error('Proxy error:', e.message);
    res.status(502).json({ error: 'Bad Gateway', message: e.message });
  }
});


app.listen(PORT, () => {
  console.log('🚀 Tor Web Bridge Running on port', PORT);
});
EOF

# Add .env
RUN cat > .env << 'EOF'
PORT=3000
NODE_ENV=production
EOF

# Add .dockerignore
RUN cat > .dockerignore << 'EOF'
node_modules
npm-debug.log
.env
.git
.gitignore
README.md
.dockerignore
EOF

# Install dependencies
RUN npm install

# Expose port
EXPOSE 3000

# Start Tor and then Node.js
CMD tor & \
    echo "🧅 Starting Tor..." && \
    sleep 30 && \
    echo "🚀 Starting Node.js app..." && \
    node server.js
