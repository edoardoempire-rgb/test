import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { ALLOW_WEB_DEMO, EXECUTOR_MODE, HELPER_INSTALL_URL, OTA, PORT, PUBLIC_BASE_URL, PUBLIC_KEY_RAW_BASE64, SERVER_BRIDGE_ADDRESS, SERVER_BRIDGE_BINARY, SERVER_BRIDGE_BIND, SERVER_BRIDGE_DEVICE_ENDPOINT, SERVER_BRIDGE_DNS_BIND, SERVER_BRIDGE_DNS_PORT, SERVER_BRIDGE_DOMAIN, SERVER_BRIDGE_ENABLED, SERVER_BRIDGE_PAIR_PORT, SERVER_BRIDGE_STATE_DIR, SKINBRIDGE_BUNDLE_ID, SKINBRIDGE_TITLE, SKINBRIDGE_VERSION, SUPPORT_URL, VPN_CA_CERT_BASE64, VPN_PASSWORD, VPN_REMOTE_ADDRESS, VPN_REMOTE_IDENTIFIER, VPN_USERNAME } from "./config.mjs";
import { completeJob, createJob, executeDemoJob, getJob } from "./jobs.mjs";
import { otaManifest } from "./ota.mjs";
import { ServerBridge, startDiscoveryDns } from "./server-bridge.mjs";

const webRoot = fileURLToPath(new URL("../../wallet-web/", import.meta.url));
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json", ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml", ".png": "image/png" };
const serverBridge = new ServerBridge({
  enabled: SERVER_BRIDGE_ENABLED,
  binary: SERVER_BRIDGE_BINARY,
  stateDir: SERVER_BRIDGE_STATE_DIR,
  bind: SERVER_BRIDGE_BIND,
  pairPort: SERVER_BRIDGE_PAIR_PORT,
  discoveryDomain: SERVER_BRIDGE_DOMAIN,
  bridgeAddress: SERVER_BRIDGE_ADDRESS,
  deviceEndpoint: SERVER_BRIDGE_DEVICE_ENDPOINT,
  vpnRemoteAddress: VPN_REMOTE_ADDRESS,
  vpnRemoteIdentifier: VPN_REMOTE_IDENTIFIER,
  vpnUsername: VPN_USERNAME,
  vpnPassword: VPN_PASSWORD,
  caCertificateBase64: VPN_CA_CERT_BASE64
});
if (serverBridge.configured() && process.argv[1] === fileURLToPath(import.meta.url)) {
  startDiscoveryDns(serverBridge, {
    bind: SERVER_BRIDGE_DNS_BIND,
    port: SERVER_BRIDGE_DNS_PORT,
    domain: SERVER_BRIDGE_DOMAIN,
    address: SERVER_BRIDGE_ADDRESS
  });
}

function json(res, code, value) {
  res.writeHead(code, { "content-type": "application/json", "cache-control": "no-store", "access-control-allow-origin": "*", "access-control-allow-headers": "content-type,x-result-token" });
  res.end(JSON.stringify(value));
}
function send(res, code, contentType, value) {
  res.writeHead(code, { "content-type": contentType, "cache-control": "no-store", "x-content-type-options": "nosniff" });
  res.end(value);
}
async function body(req) {
  let text = "";
  for await (const chunk of req) { text += chunk; if (text.length > 1_000_000) throw new Error("request too large"); }
  return JSON.parse(text || "{}");
}

export function handler(req, res) {
  if (req.method === "OPTIONS") return json(res, 204, {});
  const url = new URL(req.url, PUBLIC_BASE_URL);
  if (req.method === "GET" && url.pathname === "/health") return json(res, 200, { ok: true, publicKey: PUBLIC_KEY_RAW_BASE64, installer: OTA.mode });
  if (req.method === "GET" && url.pathname === "/v1/config") return json(res, 200, {
    helperInstallUrl: HELPER_INSTALL_URL || null,
    helperInstallMode: OTA.mode,
    signerSetupUrl: OTA.signerSetupUrl || null,
    supportUrl: SUPPORT_URL || null,
    webDemoEnabled: ALLOW_WEB_DEMO,
    executorMode: EXECUTOR_MODE,
    serverBridgeEnabled: serverBridge.configured(),
    jobTtlSeconds: Number(process.env.JOB_TTL_SECONDS || 120)
  });
  if (req.method === "POST" && url.pathname === "/v1/server-bridge/sessions") {
    return serverBridge.create(PUBLIC_BASE_URL).then(session => json(res, 201, session))
      .catch(error => json(res, 503, { error: error.message }));
  }
  const bridgeProfileMatch = url.pathname.match(/^\/v1\/server-bridge\/sessions\/([^/]+)\/profile\.mobileconfig$/);
  if (req.method === "GET" && bridgeProfileMatch) {
    const profile = serverBridge.profile(bridgeProfileMatch[1], url.searchParams.get("token"));
    if (!profile) return json(res, 404, { error: "pairing session not found" });
    res.writeHead(200, {
      "content-type": "application/x-apple-aspen-config",
      "content-disposition": 'attachment; filename="Wallet-Skins.mobileconfig"',
      "cache-control": "no-store",
      "x-content-type-options": "nosniff"
    });
    return res.end(profile);
  }
  const bridgeStatusMatch = url.pathname.match(/^\/v1\/server-bridge\/sessions\/([^/]+)$/);
  if (req.method === "GET" && bridgeStatusMatch) {
    const status = serverBridge.status(bridgeStatusMatch[1], url.searchParams.get("token"));
    return status ? json(res, 200, status) : json(res, 404, { error: "pairing session not found" });
  }
  if (req.method === "DELETE" && bridgeStatusMatch) {
    const cancelled = serverBridge.cancel(bridgeStatusMatch[1], url.searchParams.get("token"));
    return cancelled ? json(res, 200, { cancelled: true }) : json(res, 404, { error: "pairing session not found" });
  }
  if (req.method === "GET" && url.pathname === "/install/manifest.plist") {
    if (OTA.mode !== "ota" || !OTA.ipaUrl) return json(res, 404, { error: "installer not configured" });
    return send(res, 200, "application/xml; charset=utf-8", otaManifest({
      ipaUrl: OTA.ipaUrl,
      bundleId: SKINBRIDGE_BUNDLE_ID,
      version: SKINBRIDGE_VERSION,
      title: SKINBRIDGE_TITLE
    }));
  }
  if (req.method === "POST" && url.pathname === "/v1/jobs") return body(req).then(value => {
    const job = createJob(value);
    const id = job.envelope.payload.jobId;
    json(res, 201, { ...job, deepLink: `skinbridge://job?api=${encodeURIComponent(PUBLIC_BASE_URL)}&job=${encodeURIComponent(id)}` });
  }).catch(error => json(res, 400, { error: error.message }));
  const resultMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)\/result$/);
  if (req.method === "POST" && resultMatch) return body(req).then(value => {
    const out = completeJob(resultMatch[1], req.headers["x-result-token"], value);
    json(res, out.code, out.value || { error: out.error });
  }).catch(error => json(res, 400, { error: error.message }));
  const demoMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)\/demo-execute$/);
  if (req.method === "POST" && demoMatch) {
    if (!ALLOW_WEB_DEMO) return json(res, 403, { error: "web demo disabled" });
    const out = executeDemoJob(demoMatch[1]);
    return json(res, out.code, out.value || { error: out.error });
  }
  const jobMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)$/);
  if (req.method === "GET" && jobMatch) {
    const job = getJob(jobMatch[1]);
    return job ? json(res, 200, job) : json(res, 404, { error: "job not found" });
  }
  const requested = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
  const safe = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, "");
  readFile(join(webRoot, safe)).then(data => {
    res.writeHead(200, { "content-type": types[extname(safe)] || "application/octet-stream" }); res.end(data);
  }).catch(() => json(res, 404, { error: "not found" }));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  http.createServer(handler).listen(PORT, () => console.log(`Wallet Skins POC: ${PUBLIC_BASE_URL}`));
}
