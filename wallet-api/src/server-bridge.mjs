import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import dgram from "node:dgram";
import { join } from "node:path";

const TTL_MS = 15 * 60 * 1000;

function xml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function uuid() {
  return randomUUID().toUpperCase();
}

function secret() {
  return randomBytes(24).toString("base64url");
}

function sameSecret(actual, expected) {
  const left = Buffer.from(actual || "");
  const right = Buffer.from(expected || "");
  return left.length === right.length && timingSafeEqual(left, right);
}

function dnsName(name) {
  const labels = name.replace(/\.$/, "").split(".");
  return Buffer.concat([...labels.map(label => {
    const bytes = Buffer.from(label);
    if (!bytes.length || bytes.length > 63) throw new Error("invalid DNS label");
    return Buffer.concat([Buffer.from([bytes.length]), bytes]);
  }), Buffer.from([0])]);
}

function readDnsName(packet, start) {
  const labels = [];
  let offset = start;
  let end = start;
  let jumped = false;
  const visited = new Set();
  for (;;) {
    if (offset >= packet.length || visited.has(offset)) throw new Error("invalid DNS name");
    visited.add(offset);
    const length = packet[offset];
    if ((length & 0xc0) === 0xc0) {
      if (offset + 1 >= packet.length) throw new Error("invalid DNS pointer");
      const pointer = ((length & 0x3f) << 8) | packet[offset + 1];
      if (!jumped) end = offset + 2;
      jumped = true;
      offset = pointer;
      continue;
    }
    offset += 1;
    if (length === 0) {
      if (!jumped) end = offset;
      break;
    }
    if (offset + length > packet.length) throw new Error("invalid DNS label");
    labels.push(packet.subarray(offset, offset + length).toString("utf8"));
    offset += length;
    if (!jumped) end = offset;
  }
  return { name: labels.join(".").toLowerCase(), end };
}

function dnsRecord(name, type, value, ttl = 10) {
  const header = Buffer.alloc(10);
  header.writeUInt16BE(type, 0);
  header.writeUInt16BE(1, 2);
  header.writeUInt32BE(ttl, 4);
  header.writeUInt16BE(value.length, 8);
  return Buffer.concat([dnsName(name), header, value]);
}

function ipv4(address) {
  const parts = address.split(".").map(Number);
  if (parts.length !== 4 || parts.some(part => !Number.isInteger(part) || part < 0 || part > 255)) {
    throw new Error("bridge DNS address must be IPv4");
  }
  return Buffer.from(parts);
}

function txtData(txt = {}) {
  const entries = Object.entries(txt).map(([key, value]) => {
    const bytes = Buffer.from(`${key}=${value}`);
    if (bytes.length > 255) throw new Error("DNS TXT entry is too long");
    return Buffer.concat([Buffer.from([bytes.length]), bytes]);
  });
  return Buffer.concat(entries);
}

export function answerDiscoveryQuery(packet, discovery, { domain = "wallet.internal", address = "10.66.0.1" } = {}) {
  if (!Buffer.isBuffer(packet) || packet.length < 12 || packet.readUInt16BE(4) !== 1) return null;
  let question;
  try { question = readDnsName(packet, 12); } catch { return null; }
  if (question.end + 4 > packet.length) return null;
  const type = packet.readUInt16BE(question.end);
  const questionEnd = question.end + 4;
  const service = `_remotepairing-pairable-host._tcp.${domain}`.toLowerCase();
  const instance = `${discovery?.serviceId || ""}.${service}`.toLowerCase();
  const target = `gateway.${domain}`.toLowerCase();
  const answers = [];
  const additional = [];
  if (discovery && question.name === service && (type === 12 || type === 255)) {
    answers.push(dnsRecord(service, 12, dnsName(instance)));
    const srv = Buffer.alloc(6);
    srv.writeUInt16BE(Number(discovery.port), 4);
    additional.push(dnsRecord(instance, 33, Buffer.concat([srv, dnsName(target)])));
    additional.push(dnsRecord(instance, 16, txtData(discovery.txt)));
    additional.push(dnsRecord(target, 1, ipv4(address)));
  } else if (discovery && question.name === instance && (type === 33 || type === 255)) {
    const srv = Buffer.alloc(6);
    srv.writeUInt16BE(Number(discovery.port), 4);
    answers.push(dnsRecord(instance, 33, Buffer.concat([srv, dnsName(target)])));
    additional.push(dnsRecord(target, 1, ipv4(address)));
  } else if (discovery && question.name === instance && (type === 16 || type === 255)) {
    answers.push(dnsRecord(instance, 16, txtData(discovery.txt)));
  } else if (question.name === target && (type === 1 || type === 255)) {
    answers.push(dnsRecord(target, 1, ipv4(address)));
  }
  if (!answers.length && !additional.length) return null;
  const header = Buffer.alloc(12);
  packet.copy(header, 0, 0, 2);
  header.writeUInt16BE(0x8500, 2);
  header.writeUInt16BE(1, 4);
  header.writeUInt16BE(answers.length, 6);
  header.writeUInt16BE(0, 8);
  header.writeUInt16BE(additional.length, 10);
  return Buffer.concat([header, packet.subarray(12, questionEnd), ...answers, ...additional]);
}

export function startDiscoveryDns(bridge, { bind = "10.66.0.1", port = 53, domain = "wallet.internal", address = bind, upstreamAddress = "1.1.1.1" } = {}) {
  const socket = dgram.createSocket("udp4");
  socket.on("message", (packet, remote) => {
    const answer = answerDiscoveryQuery(packet, bridge.discovery, { domain, address });
    if (answer) {
      socket.send(answer, remote.port, remote.address);
      return;
    }
    const upstream = dgram.createSocket("udp4");
    const close = () => { try { upstream.close(); } catch {} };
    const timer = setTimeout(close, 2500);
    upstream.once("message", response => {
      clearTimeout(timer);
      socket.send(response, remote.port, remote.address, close);
    });
    upstream.once("error", () => { clearTimeout(timer); close(); });
    upstream.send(packet, 53, upstreamAddress);
  });
  socket.on("error", error => {
    bridge.dnsError = error.message;
    console.error(`Wallet Skins discovery DNS: ${error.message}`);
  });
  socket.bind(port, bind, () => console.log(`Wallet Skins discovery DNS: ${bind}:${port}`));
  return socket;
}

export function mobileConfig({
  remoteAddress,
  remoteIdentifier = remoteAddress,
  username,
  password,
  dnsAddress = "10.66.0.1",
  discoveryDomain = "wallet.internal",
  caCertificateBase64,
  organization = "Wallet Skins"
}) {
  if (!remoteAddress || !username || !password || !caCertificateBase64) {
    throw new Error("VPN profile is incomplete");
  }
  const rootId = uuid();
  const vpnId = uuid();
  const profileId = uuid();
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>PayloadContent</key><array>
    <dict>
      <key>PayloadCertificateFileName</key><string>WalletSkinsVPN-CA.cer</string>
      <key>PayloadContent</key><data>${xml(caCertificateBase64)}</data>
      <key>PayloadDescription</key><string>Verifica soltanto il server VPN Wallet Skins.</string>
      <key>PayloadDisplayName</key><string>Wallet Skins VPN CA</string>
      <key>PayloadIdentifier</key><string>com.walletskins.vpn.ca</string>
      <key>PayloadOrganization</key><string>${xml(organization)}</string>
      <key>PayloadType</key><string>com.apple.security.root</string>
      <key>PayloadUUID</key><string>${rootId}</string>
      <key>PayloadVersion</key><integer>1</integer>
    </dict>
    <dict>
      <key>PayloadDescription</key><string>Collegamento privato limitato al gateway Wallet Skins.</string>
      <key>PayloadDisplayName</key><string>Wallet Skins</string>
      <key>PayloadIdentifier</key><string>com.walletskins.vpn.connection</string>
      <key>PayloadOrganization</key><string>${xml(organization)}</string>
      <key>PayloadType</key><string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key><string>${vpnId}</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>UserDefinedName</key><string>Wallet Skins</string>
      <key>VPNType</key><string>IKEv2</string>
      <key>IKEv2</key><dict>
        <key>RemoteAddress</key><string>${xml(remoteAddress)}</string>
        <key>RemoteIdentifier</key><string>${xml(remoteIdentifier)}</string>
        <key>AuthenticationMethod</key><string>None</string>
        <key>ExtendedAuthEnabled</key><integer>1</integer>
        <key>AuthName</key><string>${xml(username)}</string>
        <key>AuthPassword</key><string>${xml(password)}</string>
        <key>DeadPeerDetectionRate</key><string>Medium</string>
        <key>DisableMOBIKE</key><integer>0</integer>
        <key>DisableRedirect</key><integer>0</integer>
        <key>EnableCertificateRevocationCheck</key><integer>0</integer>
        <key>EnablePFS</key><integer>1</integer>
        <key>IncludeAllNetworks</key><integer>0</integer>
        <key>EnforceRoutes</key><integer>0</integer>
        <key>ExcludeLocalNetworks</key><integer>1</integer>
        <key>IKESecurityAssociationParameters</key><dict>
          <key>EncryptionAlgorithm</key><string>AES-256-GCM</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>19</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
        <key>ChildSecurityAssociationParameters</key><dict>
          <key>EncryptionAlgorithm</key><string>AES-256-GCM</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>19</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
      </dict>
      <key>IPv4</key><dict><key>OverridePrimary</key><integer>0</integer></dict>
      <key>DNS</key><dict>
        <key>ServerAddresses</key><array><string>${xml(dnsAddress)}</string></array>
        <key>SupplementalMatchDomains</key><array><string>${xml(discoveryDomain)}</string></array>
        <key>SupplementalMatchDomainsNoSearch</key><true/>
      </dict>
      <key>OnDemandEnabled</key><integer>0</integer>
    </dict>
  </array>
  <key>PayloadDescription</key><string>Connessione sicura per abbinare questo iPhone a Wallet Skins. Non instrada il traffico Internet.</string>
  <key>PayloadDisplayName</key><string>Wallet Skins — Connessione iPhone</string>
  <key>PayloadIdentifier</key><string>com.walletskins.vpn.profile</string>
  <key>PayloadOrganization</key><string>${xml(organization)}</string>
  <key>PayloadRemovalDisallowed</key><false/>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadUUID</key><string>${profileId}</string>
  <key>PayloadVersion</key><integer>1</integer>
</dict></plist>`;
}

function publicSession(session) {
  return {
    id: session.id,
    state: session.state,
    expiresAt: session.expiresAt,
    profileUrl: session.profileUrl,
    pin: session.pin || null,
    deviceName: session.deviceName || null,
    compatible: session.compatible ?? null,
    error: session.error || null
  };
}

export class ServerBridge {
  constructor(options) {
    this.options = options;
    this.sessions = new Map();
    this.active = null;
    this.discovery = null;
  }

  configured() {
    const o = this.options;
    return Boolean(o.enabled && o.binary && o.vpnUsername && o.vpnPassword && o.caCertificateBase64);
  }

  async create(publicBaseUrl) {
    if (!this.configured()) throw new Error("server bridge is not configured");
    if (this.active?.child && !this.active.child.killed) this.active.child.kill("SIGTERM");
    await mkdir(this.options.stateDir, { recursive: true, mode: 0o700 });
    const id = randomUUID();
    const token = secret();
    const pairingPath = join(this.options.stateDir, `${id}.plist`);
    const session = {
      id,
      token,
      state: "starting",
      createdAt: Date.now(),
      expiresAt: new Date(Date.now() + TTL_MS).toISOString(),
      pairingPath,
      profileUrl: `${publicBaseUrl}/v1/server-bridge/sessions/${id}/profile.mobileconfig?token=${encodeURIComponent(token)}`
    };
    this.sessions.set(id, session);
    this.active = session;
    const child = spawn(this.options.binary, ["pair", pairingPath, this.options.bind, String(this.options.pairPort)], {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, RUST_LOG: "info" }
    });
    session.child = child;
    let stdout = "";
    const consume = line => this.#line(session, line);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", chunk => {
      stdout += chunk;
      const lines = stdout.split(/\r?\n/);
      stdout = lines.pop() || "";
      lines.forEach(consume);
    });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", chunk => String(chunk).split(/\r?\n/).filter(Boolean).forEach(consume));
    child.on("error", error => { session.state = "error"; session.error = error.message; });
    child.on("exit", code => {
      if (!["paired", "checking", "ready", "expired", "cancelled"].includes(session.state)) {
        session.state = "error";
        session.error ||= `gateway exited with code ${code}${session.lastLog ? `: ${session.lastLog}` : ""}`;
      }
    });
    await this.#waitReady(session);
    return { ...publicSession(session), token };
  }

  #line(session, line) {
    const match = line.match(/^(GATEWAY_READY|GATEWAY_PIN|PAIRING_COMPLETE|PAIRING_ERROR|PROBE_COMPLETE|PROBE_ERROR)\s+(\{.*\})$/);
    if (!match) {
      const safeLine = line.trim().replaceAll(/[\r\n]/g, " ").slice(0, 500);
      if (safeLine) session.lastLog = safeLine;
      return;
    }
    let value;
    try { value = JSON.parse(match[2]); } catch { return; }
    if (match[1] === "GATEWAY_READY") {
      session.state = "profile_ready";
      session.discovery = value;
      this.discovery = value;
    } else if (match[1] === "GATEWAY_PIN") {
      session.state = "pin_ready";
      session.pin = value.pin;
    } else if (match[1] === "PAIRING_COMPLETE") {
      session.state = "paired";
      session.deviceName = value.deviceName;
      session.deviceUdid = value.deviceUdid;
      this.#probe(session);
    } else if (match[1] === "PROBE_COMPLETE") {
      session.state = "ready";
      session.compatible = true;
    } else if (match[1] === "PROBE_ERROR") {
      session.state = "error";
      session.compatible = false;
      session.error = value.error || "compatibility check failed";
    } else {
      session.state = "error";
      session.error = value.error || "pairing failed";
    }
  }

  #probe(session) {
    session.state = "checking";
    const child = spawn(this.options.binary, ["probe", session.pairingPath, this.options.deviceEndpoint], {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, RUST_LOG: "info" }
    });
    session.probeChild = child;
    let output = "";
    const consume = line => this.#line(session, line);
    const receive = chunk => {
      output += chunk;
      const lines = output.split(/\r?\n/);
      output = lines.pop() || "";
      lines.forEach(consume);
    };
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", receive);
    child.stderr.on("data", receive);
    child.on("error", error => {
      session.state = "error";
      session.compatible = false;
      session.error = error.message;
    });
    child.on("exit", code => {
      if (session.state === "checking") {
        session.state = "error";
        session.compatible = false;
        session.error = `compatibility check exited with code ${code}${session.lastLog ? `: ${session.lastLog}` : ""}`;
      }
    });
  }

  async #waitReady(session) {
    const deadline = Date.now() + 8000;
    while (session.state === "starting" && Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    if (session.state === "starting") {
      session.child?.kill("SIGTERM");
      session.state = "error";
      session.error = "gateway did not become ready";
    }
    if (session.state === "error") throw new Error(session.error);
  }

  get(id, token) {
    const session = this.sessions.get(id);
    if (!session || !sameSecret(token, session.token)) return null;
    if (Date.parse(session.expiresAt) <= Date.now() && !["paired", "error"].includes(session.state)) {
      session.state = "expired";
      session.child?.kill("SIGTERM");
    }
    return session;
  }

  status(id, token) {
    const session = this.get(id, token);
    return session ? publicSession(session) : null;
  }

  cancel(id, token) {
    const session = this.get(id, token);
    if (!session) return false;
    session.state = "cancelled";
    session.child?.kill("SIGTERM");
    session.probeChild?.kill("SIGTERM");
    if (this.active === session) {
      this.active = null;
      this.discovery = null;
    }
    return true;
  }

  profile(id, token) {
    const session = this.get(id, token);
    if (!session || session.state === "expired") return null;
    const o = this.options;
    return mobileConfig({
      remoteAddress: o.vpnRemoteAddress,
      remoteIdentifier: o.vpnRemoteIdentifier,
      username: o.vpnUsername,
      password: o.vpnPassword,
      dnsAddress: o.bridgeAddress,
      discoveryDomain: o.discoveryDomain,
      caCertificateBase64: o.caCertificateBase64
    });
  }
}
