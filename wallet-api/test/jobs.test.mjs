import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { canonical, clearJobsForTest, completeJob, createJob, executeDemoJob } from "../src/jobs.mjs";
import { PUBLIC_KEY_RAW_BASE64 } from "../src/config.mjs";

test.beforeEach(clearJobsForTest);
test("creates a short-lived verifiable Ed25519 job", () => {
  const job = createJob({ action: "apply", cardRef: "demo-card", assetUrl: "/skin.png" }, 1_000);
  const { payload, signature } = job.envelope;
  assert.equal(new Date(payload.expiresAt) - new Date(payload.issuedAt), 120_000);
  const derPrefix = Buffer.from("302a300506032b6570032100", "hex");
  const key = crypto.createPublicKey({ key: Buffer.concat([derPrefix, Buffer.from(PUBLIC_KEY_RAW_BASE64, "base64")]), format: "der", type: "spki" });
  assert.equal(crypto.verify(null, Buffer.from(canonical(payload)), key, Buffer.from(signature, "base64")), true);
});
test("rejects payment credentials recursively", () => assert.throws(() => createJob({ action: "restore", cardRef: "abc", metadata: { cvv: "123" } }), /forbidden/));
test("requires the one-time result token", () => {
  const job = createJob({ action: "restore", cardRef: "demo-card" });
  const id = job.envelope.payload.jobId;
  assert.equal(completeJob(id, "wrong", { status: "succeeded" }).code, 401);
  assert.equal(completeJob(id, job.envelope.payload.resultToken, { status: "succeeded", executor: "mock" }).code, 200);
  assert.equal(completeJob(id, job.envelope.payload.resultToken, { status: "succeeded", executor: "mock" }).code, 409);
});
test("preserves opaque card reference characters used by Wallet", () => {
  const job = createJob({ action: "restore", cardRef: "AbC+123=_-opaque" });
  assert.equal(job.envelope.payload.cardRef, "AbC+123=_-opaque");
});
test("demo apply creates a backup and enables restore", () => {
  const apply = createJob({ action: "apply", cardRef: "demo-card", assetUrl: "/skin.png" });
  assert.equal(executeDemoJob(apply.envelope.payload.jobId).code, 200);
  const restore = createJob({ action: "restore", cardRef: "demo-card" });
  assert.equal(executeDemoJob(restore.envelope.payload.jobId).value.result.backupCreated, true);
});
test("demo restore is blocked without an earlier backup", () => {
  const restore = createJob({ action: "restore", cardRef: "new-card" });
  assert.equal(executeDemoJob(restore.envelope.payload.jobId).code, 409);
});
