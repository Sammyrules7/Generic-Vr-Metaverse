import assert from "node:assert/strict";
import { test } from "node:test";
import { gzipSync, gunzipSync } from "node:zlib";
import worker from "../src/worker.js";

const first = "a".repeat(40);
const second = "b".repeat(40);
const env = { ORIGIN_URL: "https://storage.example", API_ORIGIN_URL: "https://api.example" };

// The CDN belongs to fetch(), not the Worker. Verify the upstream contract;
// actual cache hits depend on Cloudflare and are not simulated here.
test("validators, HEAD, rollover, range responses, and CDN cache policy", async () => {
  const original = globalThis.fetch;
  const calls = [];
  let commit = first;
  globalThis.fetch = async (url, options = {}) => {
    url = String(url);
    if (url.endsWith("/commit.txt")) return new Response(commit);
    calls.push({ url, options });
    assert.deepEqual(options.cf, { cacheEverything: true, cacheTtlByStatus: { "200": 31536000, "201-599": -1 } });
    const etag = `"${url.includes(first) ? first : second}"`;
    const headers = { ETag: etag, "Last-Modified": "Mon, 12 Oct 2026 12:00:00 GMT", "Content-Length": "6" };
    if (options.headers.get("if-none-match") === etag || options.headers.has("if-modified-since")) return new Response(null, { status: 304, headers });
    if (options.headers.has("range")) {
      assert.equal(options.headers.get("if-range"), etag);
      return new Response("pac", { status: 206, headers: { ...headers, "Content-Range": "bytes 0-2/6", "Content-Length": "3" } });
    }
    return new Response(options.method === "HEAD" ? null : "packed", { headers });
  };
  const request = (path, options) => worker.fetch(new Request(`https://app.vr.maio-tech.com${path}`, options), env);
  try {
    let r = await request("/multiplayer/index.pck");
    assert.equal(await r.text(), "packed");
    assert.match(r.headers.get("cache-control"), /must-revalidate/);
    assert.equal(r.headers.get("Cross-Origin-Embedder-Policy"), "require-corp");
    r = await request("/multiplayer/index.pck", { headers: { "If-None-Match": `"${first}"` } });
    assert.equal(r.status, 304);
    assert.equal(await r.text(), "");
    r = await request("/multiplayer/index.pck", { headers: { "If-Modified-Since": "Mon, 12 Oct 2026 12:00:00 GMT" } });
    assert.equal(r.status, 304);
    r = await request("/multiplayer/index.pck", { method: "HEAD" });
    assert.equal(await r.text(), "");
    assert.equal(r.headers.get("content-length"), "6");
    commit = second;
    r = await request("/multiplayer/index.pck", { headers: { "If-None-Match": `"${first}"` } });
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("etag"), `"${second}"`);
    r = await request(`/multiplayer/${first}/index.pck`);
    assert.match(r.headers.get("cache-control"), /immutable/);
    assert.equal(r.headers.get("etag"), `"${first}"`);
    r = await request("/multiplayer/index.pck", { headers: { Range: "bytes=0-2", "If-Range": `"${second}"` } });
    assert.equal(r.status, 206);
    assert.equal(await r.text(), "pac");
    assert.ok(calls.every(x => !x.url.includes("?")));
  } finally { globalThis.fetch = original; }
});

test("gzip negotiation, validators, MIME types, ranges, and missing compressed siblings", async () => {
  const original = globalThis.fetch;
  const plain = Buffer.from("world assets ".repeat(100));
  const compressed = gzipSync(plain);
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push(String(url));
    assert.equal(options.headers.get("accept-encoding"), "identity");
    if (String(url).endsWith("old.pck.gz")) return new Response(null, { status: 404 });
    const encoded = String(url).endsWith(".gz");
    const headers = { ETag: encoded ? '"gzip"' : '"raw"', "Content-Type": encoded ? "application/gzip" : "application/octet-stream" };
    if (options.headers.get("if-none-match") === headers.ETag) return new Response(null, { status: 304, headers });
    if (options.headers.has("range")) {
      assert.equal(encoded, false);
      return new Response("world", { status: 206, headers });
    }
    return new Response(options.method === "HEAD" ? null : encoded ? compressed : plain, { headers });
  };
  const request = (asset, headers, method = "GET", preferences) => {
    const incoming = new Request(`https://app.vr.maio-tech.com/multiplayer/${first}/${asset}`, { method, headers });
    if (preferences !== undefined) Object.defineProperty(incoming, "cf", { value: { clientAcceptEncoding: preferences } });
    return worker.fetch(incoming, env);
  };
  try {
    for (const [asset, mime] of [["index.pck", "application/octet-stream"], ["index.wasm", "application/wasm"], ["index.js", "text/javascript"]]) {
      const r = await request(asset, { "Accept-Encoding": "br, gzip" });
      assert.equal(r.headers.get("content-encoding"), "gzip");
      assert.equal(r.headers.get("content-type"), mime);
      assert.match(r.headers.get("vary"), /Accept-Encoding/);
      assert.deepEqual(gunzipSync(Buffer.from(await r.arrayBuffer())), plain);
    }
    let r = await request("index.pck", { "Accept-Encoding": "gzip", "If-None-Match": '"gzip"' });
    assert.equal(r.status, 304);
    r = await request("index.pck", { "Accept-Encoding": "gzip" }, "HEAD");
    assert.equal(await r.text(), "");
    assert.equal(r.headers.get("content-encoding"), "gzip");
    for (const [header, cf] of [["gzip;q=0, *;q=1", undefined], ["br, gzip", "gzip;q=0"]]) {
      r = await request("index.pck", { "Accept-Encoding": header }, "GET", cf);
      assert.equal(r.headers.get("content-encoding"), null);
      assert.deepEqual(Buffer.from(await r.arrayBuffer()), plain);
    }
    r = await request("index.pck", { "Accept-Encoding": "gzip", Range: "bytes=0-4" });
    assert.equal(r.status, 206);
    assert.equal(r.headers.get("content-encoding"), null);
    assert.equal(await r.text(), "world");
    r = await request("old.pck", { "Accept-Encoding": "gzip" });
    assert.equal(r.headers.get("content-encoding"), null);
    assert.deepEqual(Buffer.from(await r.arrayBuffer()), plain);
    assert.ok(calls.at(-2).endsWith("old.pck.gz") && calls.at(-1).endsWith("old.pck"));
  } finally { globalThis.fetch = original; }
});

test("live HTML pins relative assets while keeping the address; pinned assets skip pointers", async () => {
  const original = globalThis.fetch;
  const calls = [];
  let commit = first;
  const html = '<html><head><title>VR</title></head><body><script src="index.js"></script></body></html>';
  globalThis.fetch = async (url, options = {}) => {
    calls.push(String(url));
    if (String(url).endsWith("branches/index.html/commit.txt")) return new Response(null, { status: 404 });
    if (String(url).endsWith("/commit.txt")) return new Response(commit);
    assert.equal(options.headers.get("if-none-match"), null);
    assert.equal(options.headers.get("range"), null);
    return new Response(options.method === "HEAD" ? null : html, { headers: { "Content-Type": "text/html", ETag: '"origin"', "Last-Modified": "yesterday", "Content-Length": String(html.length) } });
  };
  const request = (path, options) => worker.fetch(new Request(`https://app.vr.maio-tech.com${path}`, options), env);
  try {
    for (const [path, base] of [["/", `/_main/${first}/`], ["/multiplayer/", `/multiplayer/${first}/`], ["/multiplayer/sub/index.html", `/multiplayer/${first}/sub/`]]) {
      const r = await request(path, { headers: { "If-None-Match": '"origin"', Range: "bytes=0-5" } });
      assert.equal(r.status, 200);
      assert.equal(r.headers.get("location"), null);
      assert.equal(r.headers.get("etag"), null);
      assert.equal(r.headers.get("content-length"), null);
      assert.ok((await r.text()).includes(`<head><base href="${base}">`));
      assert.equal(new URL("index.pck", `https://app.vr.maio-tech.com${base}`).pathname, `${base}index.pck`);
    }
    commit = second;
    const r = await request("/multiplayer/");
    assert.ok((await r.text()).includes(`/multiplayer/${second}/`));
    calls.length = 0;
    const pinned = await request(`/multiplayer/${first}/index.html`);
    assert.equal(await pinned.text(), html);
    assert.equal(calls.length, 1);
    assert.ok(!calls[0].endsWith("commit.txt"));
    const head = await request("/multiplayer/", { method: "HEAD" });
    assert.equal(await head.text(), "");
    assert.equal(head.headers.get("etag"), null);
    assert.equal(head.headers.get("content-length"), null);
  } finally { globalThis.fetch = original; }
});

test("legacy storage never mislabels raw bytes as gzip or caches mutable objects immutably", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    if (String(url).endsWith("/commit.txt")) return new Response(first);
    if (String(url).includes("/builds/")) return new Response(null, { status: 404 });
    assert.equal(options.cf.cacheTtl, 0);
    return new Response("legacy", { headers: { "Content-Type": "application/octet-stream" } });
  };
  try {
    const r = await worker.fetch(new Request(`https://app.vr.maio-tech.com/multiplayer/${first}/index.pck`, { headers: { "Accept-Encoding": "gzip" } }), env);
    assert.equal(await r.text(), "legacy");
    assert.equal(r.headers.get("content-encoding"), null);
    assert.match(r.headers.get("cache-control"), /must-revalidate/);
  } finally { globalThis.fetch = original; }
});

test("API passthrough supports POST and cannot replace the upstream hostname", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async request => {
    assert.equal(new URL(request.url).hostname, "api.example");
    assert.equal(request.method, "POST");
    assert.equal(await request.text(), "payload");
    return new Response("ok");
  };
  try {
    const r = await worker.fetch(new Request("https://api.vr.maio-tech.com//other.example/ws", { method: "POST", body: "payload" }), env);
    assert.equal(await r.text(), "ok");
    const denied = await worker.fetch(new Request("https://app.vr.maio-tech.com/", { method: "POST" }), env);
    assert.equal(denied.status, 405);
  } finally { globalThis.fetch = original; }
});

test("avatar proxy adds CORS/isolation headers and retries rejected IPFS gateways", async () => {
  const { default: catalog } = await import("../../Godot/avatar/catalog.json", { with: { type: "json" } });
  const entry = catalog.find(e => e.thumbnail_url?.includes("QmbWYPAuKNsRUopszrvuNbL1Kkpzg5LaWW4jDVfrHc3oeB"));
  assert.ok(entry, "reported failing thumbnail must be in the catalog");
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (target, options) => {
    calls.push(String(target));
    assert.equal(options.headers.get("cookie"), null);
    assert.equal(options.headers.get("authorization"), null);
    assert.equal(options.redirect, "follow");
    assert.match(options.headers.get("user-agent"), /GenericVRPlatform/);
    if (String(target).startsWith("https://dweb.link/")) return new Response("denied", { status: 403 });
    assert.equal(new URL(target).pathname, new URL(entry.thumbnail_url).pathname);
    return new Response("image", { headers: { "Content-Type": "image/png", ETag: '"avatar"' } });
  };
  try {
    const response = await worker.fetch(new Request(`https://app.vr.maio-tech.com/avatar-assets/${entry.id}/thumbnail`, {
      headers: { Cookie: "private", Authorization: "private" },
    }), env);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "image");
    assert.equal(calls.length, 2);
    assert.equal(new URL(calls[1]).hostname, "ipfs.filebase.io");
    assert.equal(response.headers.get("access-control-allow-origin"), "*");
    assert.equal(response.headers.get("cross-origin-resource-policy"), "cross-origin");
    assert.equal(response.headers.get("cross-origin-embedder-policy"), "require-corp");
    assert.equal(response.headers.get("etag"), '"avatar"');
  } finally { globalThis.fetch = original; }
});

test("avatar proxy validates IDs, handles OPTIONS/HEAD/ranges, and does not cache failures", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (_target, options) => {
    calls++;
    if (options.headers.has("range")) return new Response("part", { status: 206, headers: { "Content-Range": "bytes 0-3/8" } });
    return new Response(null, { headers: { "Content-Length": "8" } });
  };
  const request = (suffix, options) => worker.fetch(new Request(`https://app.vr.maio-tech.com/avatar-assets/${suffix}`, options), env);
  try {
    assert.equal((await request("unknown/model?url=https://private.invalid")).status, 404);
    assert.equal((await request("godette/invalid")).status, 404);
    assert.equal(calls, 0);
    const preflight = await request("godette/model", { method: "OPTIONS" });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get("access-control-allow-origin"), "*");
    assert.equal((await request("godette/model", { method: "POST" })).status, 405);
    const head = await request("godette/model", { method: "HEAD" });
    assert.equal(head.headers.get("content-length"), "8");
    assert.equal(await head.text(), "");
    const range = await request("godette/model", { headers: { Range: "bytes=0-3" } });
    assert.equal(range.status, 206);
    assert.equal(range.headers.get("content-range"), "bytes 0-3/8");
    globalThis.fetch = async () => new Response("unavailable", { status: 503 });
    const failed = await request("godette/model");
    assert.equal(failed.status, 502);
    assert.equal(failed.headers.get("cache-control"), "no-store");
    assert.equal(failed.headers.get("access-control-allow-origin"), "*");
  } finally { globalThis.fetch = original; }
});

test("Arweave avatars use raw bytes without sandbox redirects", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (url, options) => {
    calls++;
    assert.equal(String(url), "https://arweave.net/raw/2EQ5wsstsJaFOG9LXq_gVFKKgM8bnfPa3axYJ-VS1ug");
    assert.match(options.headers.get("user-agent"), /GenericVRPlatform/);
    const bytes = new Uint8Array(20);
    const view = new DataView(bytes.buffer);
    view.setUint32(0, 0x46546c67, true);
    view.setUint32(4, 2, true);
    view.setUint32(8, 20, true);
    return new Response(bytes, { headers: { "Content-Type": "application/octet-stream" } });
  };
  try {
    const response = await worker.fetch(new Request("https://app.vr.maio-tech.com/avatar-assets/osa-ae4512a8e259ca3a47c05e9b612ccf039671333b/model?v=8a473f2c98c8171d"), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-length"), "20");
    assert.equal((await response.arrayBuffer()).byteLength, 20);
    assert.equal(calls, 1);
  } finally { globalThis.fetch = original; }
});
