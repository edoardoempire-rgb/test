import crypto from "node:crypto";
import { JOB_TTL_SECONDS, KEY_ID, PRIVATE_KEY, PUBLIC_BASE_URL, WEB_CALLBACK_URL } from "./config.mjs";

const jobs = new Map();
const demoBackups = new Set();
const forbiddenKeys = /^(pan|cvv|cvc|cardnumber|paymenttoken|trackdata)$/i;

function rejectPaymentData(value, path = "body") {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (forbiddenKeys.test(key.replaceAll(/[_-]/g, ""))) {
      throw new Error(`Payment credential field is forbidden: ${path}.${key}`);
    }
    rejectPaymentData(child, `${path}.${key}`);
  }
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function createJob(input, now = Date.now()) {
  rejectPaymentData(input);
  if (!input || !["apply", "restore"].includes(input.action)) throw new Error("action must be apply or restore");
  if (!/^[A-Za-z0-9._+=-]{3,128}$/.test(input.cardRef || "")) throw new Error("cardRef must be an opaque 3-128 character reference");
  if (input.action === "apply" && !input.assetUrl) throw new Error("assetUrl is required for apply");

  const id = crypto.randomUUID();
  const resultToken = crypto.randomBytes(24).toString("base64url");
  const payload = {
    v: 1,
    jobId: id,
    action: input.action,
    cardRef: input.cardRef,
    callbackUrl: WEB_CALLBACK_URL,
    resultUrl: `${PUBLIC_BASE_URL}/v1/jobs/${id}/result`,
    resultToken,
    issuedAt: new Date(now).toISOString(),
    expiresAt: new Date(now + JOB_TTL_SECONDS * 1000).toISOString(),
    nonce: crypto.randomBytes(16).toString("base64url")
  };
  if (input.action === "apply") payload.assetUrl = new URL(input.assetUrl, PUBLIC_BASE_URL).href;
  const signature = crypto.sign(null, Buffer.from(canonical(payload)), PRIVATE_KEY).toString("base64");
  const record = { envelope: { payload, signature, keyId: KEY_ID }, status: "created", result: null };
  jobs.set(id, record);
  return publicRecord(record);
}

export function getJob(id) {
  const record = jobs.get(id);
  return record && publicRecord(record);
}

export function completeJob(id, token, result) {
  const record = jobs.get(id);
  if (!record) return { code: 404, error: "job not found" };
  if (record.status !== "created") return { code: 409, error: "job already consumed" };
  if (new Date(record.envelope.payload.expiresAt) <= new Date()) return { code: 410, error: "job expired" };
  const supplied = Buffer.from(token || "");
  const expected = Buffer.from(record.envelope.payload.resultToken);
  if (supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) {
    return { code: 401, error: "invalid result token" };
  }
  if (!["succeeded", "failed", "incompatible"].includes(result?.status)) return { code: 400, error: "invalid status" };
  record.status = result.status;
  record.result = { ...result, completedAt: new Date().toISOString() };
  return { code: 200, value: publicRecord(record) };
}

export function executeDemoJob(id) {
  const record = jobs.get(id);
  if (!record) return { code: 404, error: "job not found" };
  const payload = record.envelope.payload;
  if (new Date(payload.expiresAt) <= new Date()) return { code: 410, error: "job expired" };
  if (record.status !== "created") return { code: 409, error: "job already consumed" };
  if (payload.action === "restore" && !demoBackups.has(payload.cardRef)) {
    return { code: 409, error: "Prima applica una skin demo per creare il backup locale simulato." };
  }
  if (payload.action === "apply") demoBackups.add(payload.cardRef);
  record.status = "succeeded";
  record.result = {
    status: "succeeded",
    executor: "web-demo",
    message: payload.action === "apply"
      ? "Skin applicata in modalità demo; Wallet non è stato modificato."
      : "Backup ripristinato in modalità demo; Wallet non è stato modificato.",
    backupCreated: demoBackups.has(payload.cardRef),
    completedAt: new Date().toISOString()
  };
  return { code: 200, value: publicRecord(record) };
}

function publicRecord(record) {
  return { envelope: record.envelope, status: record.status, result: record.result };
}

export function clearJobsForTest() { jobs.clear(); demoBackups.clear(); }
export { canonical, rejectPaymentData };
