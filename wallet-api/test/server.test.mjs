import test from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { handler } from "../src/server.mjs";
import { clearJobsForTest } from "../src/jobs.mjs";

function request(method, url, value) {
  return new Promise(resolve => {
    const req = Readable.from(value === undefined ? [] : [JSON.stringify(value)]);
    Object.assign(req, { method, url, headers: {} });
    const response = { code: 0, headers: {}, writeHead(code, headers) { this.code = code; this.headers = headers; }, end(data = "") { resolve({ code: this.code, headers: this.headers, body: data ? JSON.parse(String(data)) : null }); } };
    handler(req, response);
  });
}

test.beforeEach(clearJobsForTest);
test("configuration exposes the guided demo capability", async () => {
  const response = await request("GET", "/v1/config");
  assert.equal(response.code, 200);
  assert.equal(response.body.webDemoEnabled, true);
});

test("HTTP flow creates and executes a demo job", async () => {
  const created = await request("POST", "/v1/jobs", { action: "apply", cardRef: "demo-card", assetUrl: "/skins/aurora.png" });
  assert.equal(created.code, 201);
  assert.match(created.body.deepLink, /^skinbridge:\/\/job\?/);
  const id = created.body.envelope.payload.jobId;
  const executed = await request("POST", `/v1/jobs/${id}/demo-execute`);
  assert.equal(executed.code, 200);
  assert.equal(executed.body.result.executor, "web-demo");
});
