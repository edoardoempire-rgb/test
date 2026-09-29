import assert from "node:assert/strict";
import test from "node:test";
import { answerDiscoveryQuery, mobileConfig, ServerBridge } from "../src/server-bridge.mjs";

function dnsQuery(name, type = 12) {
  const labels = name.split(".").flatMap(label => [Buffer.from([Buffer.byteLength(label)]), Buffer.from(label)]);
  const header = Buffer.alloc(12);
  header.writeUInt16BE(0x1234, 0);
  header.writeUInt16BE(0x0100, 2);
  header.writeUInt16BE(1, 4);
  const tail = Buffer.alloc(5);
  tail.writeUInt16BE(type, 1);
  tail.writeUInt16BE(1, 3);
  return Buffer.concat([header, ...labels, tail]);
}

test("mobileConfig creates an IKEv2 profile with split DNS and embedded credentials", () => {
  const profile = mobileConfig({
    remoteAddress: "vpn.example.com",
    username: "iphone-test",
    password: "a&b<c",
    caCertificateBase64: "AQID",
    dnsAddress: "10.66.0.1",
    discoveryDomain: "wallet.internal"
  });
  assert.match(profile, /<string>IKEv2<\/string>/);
  assert.match(profile, /<string>vpn\.example\.com<\/string>/);
  assert.match(profile, /<string>a&amp;b&lt;c<\/string>/);
  assert.match(profile, /<string>10\.66\.0\.1<\/string>/);
  assert.match(profile, /<string>wallet\.internal<\/string>/);
  assert.match(profile, /com\.apple\.security\.root/);
  assert.doesNotMatch(profile, /OverridePrimary<\/key><integer>1/);
  assert.match(profile, /IncludeAllNetworks<\/key><integer>0/);
  assert.match(profile, /SearchDomains<\/key><array><string>wallet\.internal<\/string><\/array>/);
  assert.match(profile, /SupplementalMatchDomainsNoSearch<\/key><false\/>/);
  assert.match(profile, /OnDemandEnabled<\/key><integer>0/);
  assert.doesNotMatch(profile, /<string>Connect<\/string>/);
});

test("server bridge remains unavailable until every sensitive VPN setting exists", () => {
  const bridge = new ServerBridge({ enabled: true, binary: "/missing", vpnUsername: "", vpnPassword: "", caCertificateBase64: "" });
  assert.equal(bridge.configured(), false);
});

test("discovery DNS answers the RemotePairing browse query with PTR, SRV, TXT and A", () => {
  const query = dnsQuery("_remotepairing-pairable-host._tcp.wallet.internal");
  const response = answerDiscoveryQuery(query, {
    serviceId: "ABC-123",
    port: 49153,
    txt: { model: "Mac17,7", name: "Wallet Skins Gateway" }
  });
  assert.equal(response.readUInt16BE(0), 0x1234);
  assert.equal(response.readUInt16BE(6), 1);
  assert.equal(response.readUInt16BE(10), 3);
  assert.ok(response.includes(Buffer.from("abc-123")));
  assert.ok(response.includes(Buffer.from("Wallet Skins Gateway")));
});

test("discovery DNS leaves unrelated internet names to the upstream resolver", () => {
  const query = dnsQuery("www.example.com", 1);
  assert.equal(answerDiscoveryQuery(query, { serviceId: "ABC", port: 49153, txt: {} }), null);
});

test("discovery DNS advertises the wide-area Bonjour browse domain", () => {
  const response = answerDiscoveryQuery(
    dnsQuery("b._dns-sd._udp.wallet.internal"),
    { serviceId: "ABC", port: 49153, txt: {} }
  );
  assert.equal(response.readUInt16BE(6), 1);
  assert.ok(response.includes(Buffer.from("wallet")));
  assert.ok(response.includes(Buffer.from("internal")));
});

test("discovery DNS enumerates the RemotePairing service type", () => {
  const response = answerDiscoveryQuery(
    dnsQuery("_services._dns-sd._udp.wallet.internal"),
    { serviceId: "ABC", port: 49153, txt: {} }
  );
  assert.equal(response.readUInt16BE(6), 1);
  assert.ok(response.includes(Buffer.from("_remotepairing-pairable-host")));
});
