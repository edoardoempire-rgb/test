import { otaSettings } from "./ota.mjs";

export const PORT = Number(process.env.PORT || 8787);
export const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;
export const WEB_CALLBACK_URL = process.env.WEB_CALLBACK_URL || `${PUBLIC_BASE_URL}/callback.html`;
export const JOB_TTL_SECONDS = Math.min(Number(process.env.JOB_TTL_SECONDS || 120), 300);
export const KEY_ID = "poc-ed25519-2026-01";
export const DEV_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIGgBtGQ9xKCfBkbHFqYZW+rVe2kmFrUYQfXZ6ETVNX2U
-----END PRIVATE KEY-----`;
export const PRIVATE_KEY = process.env.JOB_SIGNING_PRIVATE_KEY || DEV_PRIVATE_KEY;
export const PUBLIC_KEY_RAW_BASE64 = "L0kDZm2ynYPAhFweDg4dbY3K1NJEtXb1sJP6HL+YX/k=";
export const SKINBRIDGE_IPA_URL = process.env.SKINBRIDGE_IPA_URL || "";
export const SKINBRIDGE_SIDELOAD_IPA_URL = process.env.SKINBRIDGE_SIDELOAD_IPA_URL || "";
export const SIDESTORE_SETUP_URL = process.env.SIDESTORE_SETUP_URL || "https://sideinstaller.net/";
export const SKINBRIDGE_BUNDLE_ID = process.env.SKINBRIDGE_BUNDLE_ID || "com.walletskins.skinbridge";
export const SKINBRIDGE_VERSION = process.env.SKINBRIDGE_VERSION || "0.1.0";
export const SKINBRIDGE_TITLE = process.env.SKINBRIDGE_TITLE || "SkinBridge";
export const OTA = otaSettings({ publicBaseUrl: PUBLIC_BASE_URL, explicitInstallUrl: process.env.HELPER_INSTALL_URL || "", ipaUrl: SKINBRIDGE_IPA_URL, sideloadIpaUrl: SKINBRIDGE_SIDELOAD_IPA_URL, signerSetupUrl: SIDESTORE_SETUP_URL });
export const HELPER_INSTALL_URL = OTA.installUrl;
export const SUPPORT_URL = process.env.SUPPORT_URL || "";
export const ALLOW_WEB_DEMO = process.env.ALLOW_WEB_DEMO !== "false";
export const EXECUTOR_MODE = process.env.EXECUTOR_MODE || "mock";
