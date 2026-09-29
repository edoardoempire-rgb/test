import assert from "node:assert/strict";
import test from "node:test";
import { mobileConfig, ServerBridge } from "../src/server-bridge.mjs";

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
});

test("server bridge remains unavailable until every sensitive VPN setting exists", () => {
  const bridge = new ServerBridge({ enabled: true, binary: "/missing", vpnUsername: "", vpnPassword: "", caCertificateBase64: "" });
  assert.equal(bridge.configured(), false);
});
