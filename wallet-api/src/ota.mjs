function httpsUrl(value, label) {
  if (!value) return "";
  let url;
  try { url = new URL(value); } catch { throw new Error(`${label} non valido`); }
  if (url.protocol !== "https:") throw new Error(`${label} deve usare HTTPS`);
  return url.toString();
}

export function otaSettings({ publicBaseUrl, explicitInstallUrl = "", ipaUrl = "", sideloadIpaUrl = "", signerSetupUrl = "https://sideinstaller.net/" }) {
  if (explicitInstallUrl) {
    return {
      installUrl: explicitInstallUrl,
      manifestUrl: "",
      ipaUrl: "",
      mode: explicitInstallUrl.includes("testflight.apple.com") ? "testflight" : "external",
      signerSetupUrl: ""
    };
  }
  if (!ipaUrl && sideloadIpaUrl) {
    const packageUrl = httpsUrl(sideloadIpaUrl, "SKINBRIDGE_SIDELOAD_IPA_URL");
    return {
      installUrl: `sidestore://install?url=${encodeURIComponent(packageUrl)}`,
      manifestUrl: "",
      ipaUrl: packageUrl,
      mode: "sidestore",
      signerSetupUrl: httpsUrl(signerSetupUrl, "SIDESTORE_SETUP_URL")
    };
  }
  if (!ipaUrl) return { installUrl: "", manifestUrl: "", ipaUrl: "", mode: null, signerSetupUrl: "" };
  const base = httpsUrl(publicBaseUrl, "PUBLIC_BASE_URL").replace(/\/$/, "");
  const packageUrl = httpsUrl(ipaUrl, "SKINBRIDGE_IPA_URL");
  const manifestUrl = `${base}/install/manifest.plist`;
  return {
    installUrl: `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}`,
    manifestUrl,
    ipaUrl: packageUrl,
    mode: "ota",
    signerSetupUrl: ""
  };
}

function xml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

export function otaManifest({ ipaUrl, bundleId, version, title }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${xml(ipaUrl)}</string></dict></array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>${xml(bundleId)}</string>
<key>bundle-version</key><string>${xml(version)}</string>
<key>kind</key><string>software</string>
<key>title</key><string>${xml(title)}</string>
</dict></dict></array></dict></plist>`;
}
