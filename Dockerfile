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
"use strict";var __getOwnPropNames=Object.getOwnPropertyNames,__commonJS=(t,e)=>function(){return e||(0,t[__getOwnPropNames(t)[0]])((e={exports:{}}).exports,e),e.exports},require_agent=__commonJS({"dist/cjs/agent.js"(t){Object.defineProperty(t,"__esModule",{value:!0}),t.HttpsAgent=t.HttpAgent=void 0;var e=require("http"),o=require("https"),r=class extends e.Agent{constructor(t){super(t),this.socksSocket=t.socksSocket}createConnection(){return this.socksSocket}};t.HttpAgent=r;var s=class extends o.Agent{constructor(t){super(t),this.socksSocket=t.socksSocket}createConnection(){return this.socksSocket}};t.HttpsAgent=s}}),require_constants=__commonJS({"dist/cjs/constants.js"(t){var e,o;Object.defineProperty(t,"__esModule",{value:!0}),t.headers=t.MimeTypes=t.ALLOWED_PROTOCOLS=t.HttpMethod=void 0,(e=t.HttpMethod||(t.HttpMethod={})).POST="POST",e.GET="GET",e.DELETE="DELETE",e.PUT="PUT",e.PATCH="PATCH",t.ALLOWED_PROTOCOLS=["http:","https:"],(o=t.MimeTypes||(t.MimeTypes={})).JSON="application/json",o.HTML="text/html",o.FORM="application/x-www-form-urlencoded",t.headers={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"}}}),require_utils=__commonJS({"dist/cjs/utils.js"(t){Object.defineProperty(t,"__esModule",{value:!0}),t.preventDNSLookup=t.getPath=t.buildResponse=void 0;var e=require("crypto"),o=require("path");t.buildResponse=function(t,e){return{status:t.statusCode||200,headers:t.headers,data:e}},t.getPath=function(t,r){const s=t.filename||function(t){const o=t.split("/").pop();return o&&""!==o?`${o}`:`${Date.now()}${(0,e.randomBytes)(6).toString("hex")}`}(r),n=t.dir||"./";return(0,o.isAbsolute)(n)?(0,o.join)(n,s):(0,o.join)(process.cwd(),n,s)},t.preventDNSLookup=function(t,e,o){throw new Error(`Blocked DNS lookup for: ${t}`)}}}),require_exceptions=__commonJS({"dist/cjs/exceptions.js"(t){Object.defineProperty(t,"__esModule",{value:!0}),t.TorHttpException=void 0;var e=class extends Error{constructor(t){super(`[HTTP]: ${t}`)}};t.TorHttpException=e}}),require_http=__commonJS({"dist/cjs/http.js"(t){var e=t&&t.__importDefault||function(t){return t&&t.__esModule?t:{default:t}};Object.defineProperty(t,"__esModule",{value:!0}),t.HttpClient=void 0;var o=require("fs"),r=e(require("http")),s=e(require("https")),n=e(require("querystring")),i=require_constants(),c=require_constants(),u=require_utils(),a=require_exceptions();t.HttpClient=class{getClient(t){return"http:"===t?r.default:s.default}createRequestOptions(t,e){const{protocol:o}=new URL(t);if(!i.ALLOWED_PROTOCOLS.includes(o))throw new a.TorHttpException("Invalid HTTP protocol in URL");if(!e.agent)throw new a.TorHttpException("HttpAgent is required for TOR requests");return{client:this.getClient(o),requestOptions:{headers:Object.assign(Object.assign({},c.headers),e.headers),method:e.method,agent:e.agent,lookup:u.preventDNSLookup}}}request(t,e={}){const{client:o,requestOptions:r}=this.createRequestOptions(t,e);return new Promise(((s,n)=>{const i=o.request(t,r,(t=>{let e="";t.on("data",(t=>e+=t)),t.on("error",n),t.on("close",(()=>{const o=(0,u.buildResponse)(t,e);s(o)}))}));e.timeout&&i.setTimeout(e.timeout),i.on("error",n),i.on("timeout",(()=>n(new a.TorHttpException("Http request timeout")))),e.data&&i.write(e.data),i.end()}))}download(t,e){const{client:r,requestOptions:s}=this.createRequestOptions(t,e);return new Promise(((n,i)=>{const c=r.request(t,s,(t=>{const r=(0,o.createWriteStream)(e.path);t.pipe(r),t.on("error",(t=>{r.end(),i(t)})),t.on("close",(()=>{r.end(),n(e.path)}))}));e.timeout&&c.setTimeout(e.timeout),c.on("error",i),c.on("timeout",(()=>i(new a.TorHttpException("Download timeout")))),c.end()}))}delete(t,e={}){return this.request(t,Object.assign(Object.assign({},e),{method:c.HttpMethod.DELETE}))}get(t,e={}){return this.request(t,Object.assign(Object.assign({},e),{method:c.HttpMethod.GET}))}post(t,e,o={}){const r=n.default.stringify(e);return this.request(t,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.POST,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}put(t,e,o={}){const r=n.default.stringify(e);return this.request(t,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.PUT,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}patch(t,e,o={}){const r=n.default.stringify(e);return this.request(t,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.PATCH,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}}}}),require_socks=__commonJS({"dist/cjs/socks.js"(t){var e=t&&t.__createBinding||(Object.create?function(t,e,o,r){void 0===r&&(r=o);var s=Object.getOwnPropertyDescriptor(e,o);s&&!("get"in s?!e.__esModule:s.writable||s.configurable)||(s={enumerable:!0,get:function(){return e[o]}}),Object.defineProperty(t,r,s)}:function(t,e,o,r){void 0===r&&(r=o),t[r]=e[o]}),o=t&&t.__setModuleDefault||(Object.create?function(t,e){Object.defineProperty(t,"default",{enumerable:!0,value:e})}:function(t,e){t.default=e}),r=t&&t.__importStar||function(t){if(t&&t.__esModule)return t;var r={};if(null!=t)for(var s in t)"default"!==s&&Object.prototype.hasOwnProperty.call(t,s)&&e(r,t,s);return o(r,t),r},s=t&&t.__awaiter||function(t,e,o,r){return new(o||(o=Promise))((function(s,n){function i(t){try{u(r.next(t))}catch(t){n(t)}}function c(t){try{u(r.throw(t))}catch(t){n(t)}}function u(t){var e;t.done?s(t.value):(e=t.value,e instanceof o?e:new o((function(t){t(e)}))).then(i,c)}u((r=r.apply(t,e||[])).next())}))};Object.defineProperty(t,"__esModule",{value:!0}),t.Socks=void 0;var n=r(require("node:net"));t.Socks=class t{constructor(t,e){this.socket=t,this.options=e,this.onTimeout=()=>{const t=new Error("SOCKS5 connection attempt timed out");this.socket.destroy(t)},this.recv=Buffer.alloc(0),this.socket.on("timeout",this.onTimeout)}static connect(e){const o=n.default.connect({host:e.socksHost,port:e.socksPort,keepAlive:e.keepAlive,noDelay:e.noDelay,timeout:e.timeout});return new Promise(((r,s)=>{const n=t=>{o.destroy(),s(t)},i=()=>{const t=new Error("SOCKS5 connection attempt timed out");o.destroy(t)};o.once("error",n),o.once("timeout",i),o.once("connect",(()=>{o.removeListener("error",n),o.removeListener("timeout",i),r(new t(o,e))}))}))}proxy(t,e){return s(this,void 0,void 0,(function*(){return yield this.initialize(),this.request(t,e)}))}initialize(){if(this.socket.destroyed)throw new Error("SOCKS5 connection is already destroyed");const t=[5,1,0],e=Buffer.from(t);return new Promise(((t,o)=>{const r=()=>{o(new Error("SOCKS5 dropped connection"))},s=t=>{this.socket.removeListener("close",r),this.socket.destroy(),o(t)},n=e=>{let o;if(this.recv=Buffer.concat([this.recv,e]),!(this.recv.length<2)){if(5!==this.recv[0]?o=new Error("Invalid SOCKS version in response"):0!==this.recv[1]&&(o=new Error("Unexpected SOCKS authentication method")),!o)return this.recv=this.recv.subarray(2),this.socket.removeListener("data",n),this.socket.removeListener("error",s),this.socket.removeListener("close",r),t(!0);this.socket.destroy(o)}};this.socket.once("close",r),this.socket.once("error",s),this.socket.on("data",n),this.socket.write(e)}))}request(t,e){if(this.socket.destroyed)throw new Error("SOCKS5 connection is already destroyed");const o=[5,1,0,...this.parseHost(t)];o.length+=2;const r=Buffer.from(o);return r.writeUInt16BE(e,r.length-2),new Promise(((t,e)=>{let o=10;const s=()=>{e(new Error("SOCKS5 dropped connection"))},n=t=>{this.socket.removeListener("close",s),this.socket.destroy(),e(t)},i=e=>{let r;if(this.recv=Buffer.concat([this.recv,e]),this.recv.length<o)return;if(5!==this.recv[0])r=new Error("Invalid SOCKS version in response");else if(0!==this.recv[1]){const t=this.mapError(e[1]);r=new Error(t)}else 0!==this.recv[2]&&(r=new Error("Invalid SOCKS response shape"));const c=this.recv[3];if(o=6,1==c?o+=4:3==c?o+=this.recv[4]+1:4==c?o+=16:r=new Error("Unexpected address type"),r)this.socket.destroy(r);else if(!(this.recv.length<o))return this.socket.removeListener("data",i),this.socket.removeListener("error",n),this.socket.removeListener("close",s),this.socket.removeListener("timeout",this.onTimeout),this.recv=this.recv.subarray(o),this.recv.length>0&&setTimeout((()=>{this.socket.emit("data",this.recv)})),t(this.socket)};this.socket.once("error",n),this.socket.once("close",s),this.socket.on("data",i),this.socket.write(r)}))}parseHost(t){const e=(0,n.isIP)(t);if(4===e){return[1,...Buffer.from(t.split(".").map((t=>parseInt(t,10))))]}if(6===e){return[4,...Buffer.from(t.split(":").map((t=>parseInt(t,16))))]}{const e=Buffer.from(t);return[3,e.length,...e]}}mapError(t){switch(t){case 1:return"General failure";case 2:return"Connection not allowed by ruleset";case 3:return"Network unreachable";case 4:return"Host unreachable";case 5:return"Connection refused by destination host";case 6:return"TTL expired";case 7:return"Command not supported / protocol error";case 8:return"Address type not supported";default:return"Unknown SOCKS response status"}}}}}),require_tor=__commonJS({"dist/cjs/tor.js"(t){var e=t&&t.__awaiter||function(t,e,o,r){return new(o||(o=Promise))((function(s,n){function i(t){try{u(r.next(t))}catch(t){n(t)}}function c(t){try{u(r.throw(t))}catch(t){n(t)}}function u(t){var e;t.done?s(t.value):(e=t.value,e instanceof o?e:new o((function(t){t(e)}))).then(i,c)}u((r=r.apply(t,e||[])).next())}))};Object.defineProperty(t,"__esModule",{value:!0}),t.TorClient=void 0;var o=require("tls"),r=require_agent(),s=require_http(),n=require_socks(),i=require_utils();t.TorClient=class{constructor(t={}){this.http=new s.HttpClient,this.options=t}createAgent(t,e){if("http:"===t)return new r.HttpAgent({socksSocket:e});const s=new o.TLSSocket(e);return new r.HttpsAgent({socksSocket:s})}getDestination(t){const e=new URL(t);let o="http:"===e.protocol?80:443;return(e.port||""!==e.port)&&(o=parseInt(e.port)),{port:o,host:e.host,protocol:e.protocol,pathname:e.pathname}}connectSocks(t,o,r){return e(this,void 0,void 0,(function*(){const e={socksHost:this.options.socksHost||"127.0.0.1",socksPort:this.options.socksPort||9050,timeout:r};return(yield n.Socks.connect(e)).proxy(t,o)}))}download(t,o={}){return e(this,void 0,void 0,(function*(){const{protocol:e,host:r,port:s,pathname:n}=this.getDestination(t),c=(0,i.getPath)(o,n),u=yield this.connectSocks(r,s),a=this.createAgent(e,u);return this.http.download(t,{path:c,agent:a,headers:o.headers,timeout:o.timeout})}))}get(t,o={}){return e(this,void 0,void 0,(function*(){const{protocol:e,host:r,port:s}=this.getDestination(t),n=yield this.connectSocks(r,s,o.timeout),i=this.createAgent(e,n);return this.http.get(t,{agent:i,headers:o.headers,timeout:o.timeout})}))}post(t,o,r={}){return e(this,void 0,void 0,(function*(){const{protocol:e,host:s,port:n}=this.getDestination(t),i=yield this.connectSocks(s,n),c=this.createAgent(e,i);return this.http.post(t,o,{agent:c,headers:r.headers,timeout:r.timeout})}))}request(t,o={}){return e(this,void 0,void 0,(function*(){const{protocol:e,host:r,port:s}=this.getDestination(t),n=yield this.connectSocks(r,s),i=this.createAgent(e,n);return this.http.request(t,{agent:i,method:o.method,headers:o.headers,data:o.data,timeout:o.timeout})}))}torcheck(t){return e(this,void 0,void 0,(function*(){const e=yield this.get("https://check.torproject.org/",t);if(!e.status||200!==e.status)throw new Error(`Network error with check.torproject.org, status code: ${e.status}`);return e.data.includes("Congratulations. This browser is configured to use Tor")}))}}}});Object.defineProperty(exports,"__esModule",{value:!0}),exports.Socks=exports.TorClient=void 0;var tor_1=require_tor();Object.defineProperty(exports,"TorClient",{enumerable:!0,get:function(){return tor_1.TorClient}});var socks_1=require_socks();Object.defineProperty(exports,"Socks",{enumerable:!0,get:function(){return socks_1.Socks}});
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
