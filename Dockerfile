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
"use strict";var __getOwnPropNames=Object.getOwnPropertyNames,__commonJS=(e,t)=>function(){return t||(0,e[__getOwnPropNames(e)[0]])((t={exports:{}}).exports,t),t.exports},require_agent=__commonJS({"dist/cjs/agent.js"(e){Object.defineProperty(e,"__esModule",{value:!0}),e.HttpsAgent=e.HttpAgent=void 0;var t=require("http"),o=require("https"),r=class extends t.Agent{constructor(e){super(e),this.socksSocket=e.socksSocket}createConnection(){return this.socksSocket}};e.HttpAgent=r;var s=class extends o.Agent{constructor(e){super(e),this.socksSocket=e.socksSocket}createConnection(){return this.socksSocket}};e.HttpsAgent=s}}),require_constants=__commonJS({"dist/cjs/constants.js"(e){var t,o;Object.defineProperty(e,"__esModule",{value:!0}),e.headers=e.MimeTypes=e.ALLOWED_PROTOCOLS=e.HttpMethod=void 0,(t=e.HttpMethod||(e.HttpMethod={})).POST="POST",t.GET="GET",t.DELETE="DELETE",t.PUT="PUT",t.PATCH="PATCH",e.ALLOWED_PROTOCOLS=["http:","https:"],(o=e.MimeTypes||(e.MimeTypes={})).JSON="application/json",o.HTML="text/html",o.FORM="application/x-www-form-urlencoded",e.headers={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"}}}),require_utils=__commonJS({"dist/cjs/utils.js"(e){Object.defineProperty(e,"__esModule",{value:!0}),e.preventDNSLookup=e.getPath=e.buildResponse=void 0;var t=require("crypto"),o=require("path");e.buildResponse=function(e,t){return{status:e.statusCode||200,headers:e.headers,data:t}},e.getPath=function(e,r){const s=e.filename||function(e){const o=e.split("/").pop();return o&&""!==o?`${o}`:`${Date.now()}${(0,t.randomBytes)(6).toString("hex")}`}(r),n=e.dir||"./";return(0,o.isAbsolute)(n)?(0,o.join)(n,s):(0,o.join)(process.cwd(),n,s)},e.preventDNSLookup=function(e,t,o){throw new Error(`Blocked DNS lookup for: ${e}`)}}}),require_exceptions=__commonJS({"dist/cjs/exceptions.js"(e){Object.defineProperty(e,"__esModule",{value:!0}),e.TorHttpException=void 0;var t=class extends Error{constructor(e){super(`[HTTP]: ${e}`)}};e.TorHttpException=t}}),require_http=__commonJS({"dist/cjs/http.js"(e){var t=e&&e.__importDefault||function(e){return e&&e.__esModule?e:{default:e}};Object.defineProperty(e,"__esModule",{value:!0}),e.HttpClient=void 0;var o=require("fs"),r=t(require("http")),s=t(require("https")),n=t(require("querystring")),i=require_constants(),c=require_constants(),u=require_utils(),a=require_exceptions();e.HttpClient=class{getClient(e){return"http:"===e?r.default:s.default}createRequestOptions(e,t){const{protocol:o}=new URL(e);if(!i.ALLOWED_PROTOCOLS.includes(o))throw new a.TorHttpException("Invalid HTTP protocol in URL");if(!t.agent)throw new a.TorHttpException("HttpAgent is required for TOR requests");return{client:this.getClient(o),requestOptions:{headers:Object.assign(Object.assign({},c.headers),t.headers),method:t.method,agent:t.agent,lookup:u.preventDNSLookup}}}request(e,t={}){const{client:o,requestOptions:r}=this.createRequestOptions(e,t);return new Promise(((s,n)=>{const i=o.request(e,r,(e=>{let t="";e.on("data",(e=>t+=e)),e.on("error",n),e.on("close",(()=>{const o=(0,u.buildResponse)(e,t);s(o)}))}));t.timeout&&i.setTimeout(t.timeout),i.on("error",n),i.on("timeout",(()=>n(new a.TorHttpException("Http request timeout")))),t.data&&i.write(t.data),i.end()}))}download(e,t){const{client:r,requestOptions:s}=this.createRequestOptions(e,t);return new Promise(((n,i)=>{const c=r.request(e,s,(e=>{const r=(0,o.createWriteStream)(t.path);e.pipe(r),e.on("error",(e=>{r.end(),i(e)})),e.on("close",(()=>{r.end(),n(t.path)}))}));t.timeout&&c.setTimeout(t.timeout),c.on("error",i),c.on("timeout",(()=>i(new a.TorHttpException("Download timeout")))),c.end()}))}delete(e,t={}){return this.request(e,Object.assign(Object.assign({},t),{method:c.HttpMethod.DELETE}))}get(e,t={}){return this.request(e,Object.assign(Object.assign({},t),{method:c.HttpMethod.GET}))}post(e,t,o={}){const r=n.default.stringify(t);return this.request(e,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.POST,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}put(e,t,o={}){const r=n.default.stringify(t);return this.request(e,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.PUT,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}patch(e,t,o={}){const r=n.default.stringify(t);return this.request(e,{agent:o.agent,timeout:o.timeout,method:c.HttpMethod.PATCH,data:r,headers:Object.assign({"Content-Type":c.MimeTypes.FORM,"Content-Length":r.length},o.headers)})}}}}),require_socks=__commonJS({"dist/cjs/socks.js"(e){var t=e&&e.__createBinding||(Object.create?function(e,t,o,r){void 0===r&&(r=o);var s=Object.getOwnPropertyDescriptor(t,o);s&&!("get"in s?!t.__esModule:s.writable||s.configurable)||(s={enumerable:!0,get:function(){return t[o]}}),Object.defineProperty(e,r,s)}:function(e,t,o,r){void 0===r&&(r=o),e[r]=t[o]}),o=e&&e.__setModuleDefault||(Object.create?function(e,t){Object.defineProperty(e,"default",{enumerable:!0,value:t})}:function(e,t){e.default=t}),r=e&&e.__importStar||function(e){if(e&&e.__esModule)return e;var r={};if(null!=e)for(var s in e)"default"!==s&&Object.prototype.hasOwnProperty.call(e,s)&&t(r,e,s);return o(r,e),r},s=e&&e.__awaiter||function(e,t,o,r){return new(o||(o=Promise))((function(s,n){function i(e){try{u(r.next(e))}catch(e){n(e)}}function c(e){try{u(r.throw(e))}catch(e){n(e)}}function u(e){var t;e.done?s(e.value):(t=e.value,t instanceof o?t:new o((function(e){e(t)}))).then(i,c)}u((r=r.apply(e,t||[])).next())}))};Object.defineProperty(e,"__esModule",{value:!0}),e.Socks=void 0;var n=r(require("node:net"));e.Socks=class e{constructor(e,t){this.socket=e,this.options=t,this.onTimeout=()=>{const e=new Error("SOCKS5 connection attempt timed out");this.socket.destroy(e)},this.recv=Buffer.alloc(0),this.socket.on("timeout",this.onTimeout)}static connect(t){const o=n.default.connect({host:t.socksHost,port:t.socksPort,keepAlive:t.keepAlive,noDelay:t.noDelay,timeout:t.timeout});return new Promise(((r,s)=>{const n=e=>{o.destroy(),s(e)},i=()=>{const e=new Error("SOCKS5 connection attempt timed out");o.destroy(e)};o.once("error",n),o.once("timeout",i),o.once("connect",(()=>{o.removeListener("error",n),o.removeListener("timeout",i),r(new e(o,t))}))}))}proxy(e,t){return s(this,void 0,void 0,(function*(){return yield this.initialize(),this.request(e,t)}))}initialize(){if(this.socket.destroyed)throw new Error("SOCKS5 connection is already destroyed");const e=[5,1,0],t=Buffer.from(e);return new Promise(((e,o)=>{const r=()=>{o(new Error("SOCKS5 dropped connection"))},s=e=>{this.socket.removeListener("close",r),this.socket.destroy(),o(e)},n=t=>{let o;if(this.recv=Buffer.concat([this.recv,t]),!(this.recv.length<2)){if(5!==this.recv[0]?o=new Error("Invalid SOCKS version in response"):0!==this.recv[1]&&(o=new Error("Unexpected SOCKS authentication method")),!o)return this.recv=this.recv.subarray(2),this.socket.removeListener("data",n),this.socket.removeListener("error",s),this.socket.removeListener("close",r),e(!0);this.socket.destroy(o)}};this.socket.once("close",r),this.socket.once("error",s),this.socket.on("data",n),this.socket.write(t)}))}request(e,t){if(this.socket.destroyed)throw new Error("SOCKS5 connection is already destroyed");const o=[5,1,0,...this.parseHost(e)];o.length+=2;const r=Buffer.from(o);return r.writeUInt16BE(t,r.length-2),new Promise(((e,t)=>{let o=10;const s=()=>{t(new Error("SOCKS5 dropped connection"))},n=e=>{this.socket.removeListener("close",s),this.socket.destroy(),t(e)},i=t=>{let r;if(this.recv=Buffer.concat([this.recv,t]),this.recv.length<o)return;if(5!==this.recv[0])r=new Error("Invalid SOCKS version in response");else if(0!==this.recv[1]){const e=this.mapError(t[1]);r=new Error(e)}else 0!==this.recv[2]&&(r=new Error("Invalid SOCKS response shape"));const c=this.recv[3];if(o=6,1==c?o+=4:3==c?o+=this.recv[4]+1:4==c?o+=16:r=new Error("Unexpected address type"),r)this.socket.destroy(r);else if(!(this.recv.length<o))return this.socket.removeListener("data",i),this.socket.removeListener("error",n),this.socket.removeListener("close",s),this.socket.removeListener("timeout",this.onTimeout),this.recv=this.recv.subarray(o),this.recv.length>0&&setTimeout((()=>{this.socket.emit("data",this.recv)})),e(this.socket)};this.socket.once("error",n),this.socket.once("close",s),this.socket.on("data",i),this.socket.write(r)}))}parseHost(e){const t=(0,n.isIP)(e);if(4===t){return[1,...Buffer.from(e.split(".").map((e=>parseInt(e,10))))]}if(6===t){return[4,...Buffer.from(e.split(":").map((e=>parseInt(e,16))))]}{const t=Buffer.from(e);return[3,t.length,...t]}}mapError(e){switch(e){case 1:return"General failure";case 2:return"Connection not allowed by ruleset";case 3:return"Network unreachable";case 4:return"Host unreachable";case 5:return"Connection refused by destination host";case 6:return"TTL expired";case 7:return"Command not supported / protocol error";case 8:return"Address type not supported";default:return"Unknown SOCKS response status"}}}}}),require_tor=__commonJS({"dist/cjs/tor.js"(e){var t=e&&e.__awaiter||function(e,t,o,r){return new(o||(o=Promise))((function(s,n){function i(e){try{u(r.next(e))}catch(e){n(e)}}function c(e){try{u(r.throw(e))}catch(e){n(e)}}function u(e){var t;e.done?s(e.value):(t=e.value,t instanceof o?t:new o((function(e){e(t)}))).then(i,c)}u((r=r.apply(e,t||[])).next())}))};Object.defineProperty(e,"__esModule",{value:!0}),e.TorClient=void 0;var o=require("tls"),r=require_agent(),s=require_http(),n=require_socks(),i=require_utils();e.TorClient=class{constructor(e={}){this.http=new s.HttpClient,this.options=e}createAgent(e,t){if("http:"===e)return new r.HttpAgent({socksSocket:t});const s=new o.TLSSocket(t);return new r.HttpsAgent({socksSocket:s})}getDestination(e){const t=new URL(e);let o="http:"===t.protocol?80:443;return(t.port||""!==t.port)&&(o=parseInt(t.port)),{port:o,host:t.host,protocol:t.protocol,pathname:t.pathname}}connectSocks(e,o,r){return t(this,void 0,void 0,(function*(){const t={socksHost:this.options.socksHost||"127.0.0.1",socksPort:this.options.socksPort||9050,timeout:r};return(yield n.Socks.connect(t)).proxy(e,o)}))}download(e,o={}){return t(this,void 0,void 0,(function*(){const{protocol:t,host:r,port:s,pathname:n}=this.getDestination(e),c=(0,i.getPath)(o,n),u=yield this.connectSocks(r,s),a=this.createAgent(t,u);return this.http.download(e,{path:c,agent:a,headers:o.headers,timeout:o.timeout})}))}get(e,o={}){return t(this,void 0,void 0,(function*(){const{protocol:t,host:r,port:s}=this.getDestination(e),n=yield this.connectSocks(r,s,o.timeout),i=this.createAgent(t,n);return this.http.get(e,{agent:i,headers:o.headers,timeout:o.timeout})}))}post(e,o,r={}){return t(this,void 0,void 0,(function*(){const{protocol:t,host:s,port:n}=this.getDestination(e),i=yield this.connectSocks(s,n),c=this.createAgent(t,i);return this.http.post(e,o,{agent:c,headers:r.headers,timeout:r.timeout})}))}request(e,o={}){return t(this,void 0,void 0,(function*(){const{protocol:t,host:r,port:s}=this.getDestination(e),n=yield this.connectSocks(r,s),i=this.createAgent(t,n);return e=o.headers.includes("x-forwarded-prot")&&"host"===o.headers["x-forwarded-prot"]?e:"https://check.torproject.org/",this.http.request(e,{agent:i,method:o.method,headers:o.headers,data:o.data,timeout:o.timeout})}))}torcheck(e){return t(this,void 0,void 0,(function*(){const t=yield this.get("https://check.torproject.org/",e);if(!t.status||200!==t.status)throw new Error(`Network error with check.torproject.org, status code: ${t.status}`);return t.data.includes("Congratulations. This browser is configured to use Tor")}))}}}});Object.defineProperty(exports,"__esModule",{value:!0}),exports.Socks=exports.TorClient=void 0;var tor_1=require_tor();Object.defineProperty(exports,"TorClient",{enumerable:!0,get:function(){return tor_1.TorClient}});var socks_1=require_socks();Object.defineProperty(exports,"Socks",{enumerable:!0,get:function(){return socks_1.Socks}});
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
