import test from "node:test";
import assert from "node:assert/strict";
import { otaManifest, otaSettings } from "../src/ota.mjs";

test("builds a one-tap OTA installation URL", () => {
  const settings = otaSettings({
    publicBaseUrl: "https://wallet.example.com",
    ipaUrl: "https://wallet.example.com/downloads/SkinBridge.ipa"
  });
  assert.equal(settings.mode, "ota");
  assert.match(settings.installUrl, /^itms-services:\/\/\?action=download-manifest&url=/);
  assert.equal(settings.manifestUrl, "https://wallet.example.com/install/manifest.plist");
});

test("rejects an insecure IPA URL", () => {
  assert.throws(() => otaSettings({ publicBaseUrl: "https://wallet.example.com", ipaUrl: "http://example.com/SkinBridge.ipa" }), /HTTPS/);
});

test("builds a free on-device SideStore installation URL", () => {
  const settings = otaSettings({
    publicBaseUrl: "https://wallet.example.com",
    sideloadIpaUrl: "https://wallet.example.com/downloads/SkinBridge-unsigned.ipa"
  });
  assert.equal(settings.mode, "sidestore");
  assert.match(settings.installUrl, /^sidestore:\/\/install\?url=/);
  assert.equal(settings.signerSetupUrl, "https://sideinstaller.net/");
});

test("generates an Apple installation manifest", () => {
  const manifest = otaManifest({ ipaUrl: "https://wallet.example.com/SkinBridge.ipa?a=1&b=2", bundleId: "com.walletskins.skinbridge", version: "1.0", title: "SkinBridge" });
  assert.match(manifest, /software-package/);
  assert.match(manifest, /com\.walletskins\.skinbridge/);
  assert.match(manifest, /a=1&amp;b=2/);
});
