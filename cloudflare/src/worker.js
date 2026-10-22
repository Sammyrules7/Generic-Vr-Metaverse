import avatarCatalog from "../../Godot/avatar/catalog.json" with { type: "json" };
const avatarById = new Map(avatarCatalog.map(entry => [entry.id, entry]));

const API_HOST = "api.vr.maio-tech.com";
const LEGACY_PREVIEW_PREFIX = "/previews/";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.hostname === API_HOST) {
        // Assign the path separately: a path beginning with // must never
        // replace the configured upstream host (or forward headers elsewhere).
        const upstream = new URL(env.API_ORIGIN_URL);
        upstream.pathname = url.pathname;
        upstream.search = url.search;
        return await fetch(new Request(upstream, request));
      }
      if (url.pathname.startsWith("/avatar-assets/")) return await avatarAsset(request, url);
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
      }

      if (url.pathname.startsWith(LEGACY_PREVIEW_PREFIX)) {
        url.pathname = url.pathname.slice("/previews".length);
        return Response.redirect(url.toString(), 301);
      }

      const target = await resolveTarget(url.pathname, env.ORIGIN_URL);
      if (!target) return notFound();
      if (target.redirect) {
        url.pathname = target.redirect;
        return new Response(null, {
          status: 302,
          headers: { Location: url.toString(), "Cache-Control": "no-store" },
        });
      }

      // Key by the immutable object, not arbitrary caller query parameters.
      const compressible = /\.(?:pck|wasm|js)$/.test(target.asset);
      // Cloudflare normalizes the header; cf retains the browser's preferences.
      const acceptEncoding = request.cf?.clientAcceptEncoding ?? request.headers.get("accept-encoding");
      const gzip = compressible && !request.headers.has("range") && acceptsGzip(acceptEncoding);
      const originHeaders = copyOriginHeaders(request.headers);
      const liveHtml = !target.pinned && target.asset.endsWith(".html");
      // Transformed HTML must always include the pinned base and fresh metadata.
      if (liveHtml) {
        for (const name of ["if-none-match", "if-modified-since", "range", "if-range"]) originHeaders.delete(name);
      }

      // Objects named .gz are stored as raw gzip bytes, without HTTP encoding
      // metadata. Avoid an extra layer of origin-side transport compression.
      originHeaders.set("Accept-Encoding", "identity");
      const originOptions = {
        method: request.method,
        headers: originHeaders,
        // Cache immutable storage objects through fetch, including Tiered Cache.
        // Never retain missing objects or incomplete responses.
        cf: { cacheEverything: true, cacheTtlByStatus: { "200": 31536000, "201-599": -1 } },
      };
      let encoded = gzip;
      let originResponse = await fetch(`${env.ORIGIN_URL}/${target.key}${encoded ? ".gz" : ""}`, originOptions);
      if (encoded && originResponse.status === 404) {
        // Existing immutable builds predate compressed siblings.
        encoded = false;
        originResponse = await fetch(`${env.ORIGIN_URL}/${target.key}`, originOptions);
      }
      // Keep builds published before versioned storage working during rollout.
      // Only the active legacy build can be served, and never cached as immutable.
      let legacy = false;
      if (originResponse.status === 404) {
        const marker = await fetch(`${env.ORIGIN_URL}/${target.prefix}/builds/${target.commit}/complete.txt`, { method: "HEAD" });
        if (marker.status === 404 && await fetchPointer(env.ORIGIN_URL, `${target.prefix}/commit.txt`) === target.commit) {
          originResponse = await fetch(`${env.ORIGIN_URL}/${target.prefix}/assets/${target.asset}`, { ...originOptions, cf: { cacheEverything: true, cacheTtl: 0 } });
          legacy = true;
        }
      }
      if (legacy) encoded = false;
      if (!originResponse.ok && originResponse.status !== 304 && originResponse.status !== 416) {
        return originResponse.status === 404
          ? notFound()
          : new Response("Build origin unavailable", { status: 502 });
      }

      const headers = new Headers(originResponse.headers);
      if (compressible) headers.append("Vary", "Accept-Encoding");
      if (encoded) {
        headers.set("Content-Encoding", "gzip");
        headers.set("Content-Type", target.asset.endsWith(".wasm") ? "application/wasm"
          : target.asset.endsWith(".js") ? "text/javascript" : "application/octet-stream");
        headers.set("Accept-Ranges", "none");
      }
      headers.set("X-Content-Type-Options", "nosniff");
      headers.set("Cross-Origin-Opener-Policy", "same-origin");
      headers.set("Cross-Origin-Embedder-Policy", "require-corp");
      const pinned = target.pinned && !legacy;
      headers.set("Cache-Control", originResponse.status === 416 ? "no-store"
        : pinned ? "public, max-age=31536000, immutable" : "public, max-age=0, must-revalidate");
      let body = request.method === "HEAD" ? null : originResponse.body;
      if (liveHtml && !legacy && originResponse.status === 200) {
        headers.delete("Content-Length");
        headers.delete("ETag");
        headers.delete("Last-Modified");
        headers.set("Accept-Ranges", "none");
        if (body) {
          const html = await originResponse.text();
          body = html.replace(/<head\b[^>]*>/i, head => `${head}<base href="${target.assetBase}">`);
        }
      }
      return new Response(body, { status: originResponse.status, headers, encodeBody: "manual" });
    } catch (error) {
      console.error(error);
      return new Response("Unable to load this web build", { status: 502 });
    }
  },
};

async function resolveTarget(pathname, origin) {
  const parts = pathname.replace(/^\/+/, "").split("/");
  const branch = parts[0];
  if (branch === "_main") {
    parts.shift();
    const commit = parts.shift();
    return isCommit(commit) ? buildTarget("channels/main", "/_main", commit, parts) : null;
  }
  if (isSlug(branch)) {
    // Pinned previews keep working after the branch publishes another build.
    if (isCommit(parts[1])) {
      return buildTarget(`branches/${branch}`, `/${branch}`, parts[1], parts.slice(2));
    }
    const commit = await fetchPointer(origin, `branches/${branch}/commit.txt`);
    if (isCommit(commit)) {
      return buildTarget(`branches/${branch}`, `/${branch}`, commit, parts.slice(1), false);
    }
  }

  const commit = await fetchPointer(origin, "channels/main/commit.txt");
  return isCommit(commit) ? buildTarget("channels/main", "", commit, parts, false) : null;
}

function buildTarget(prefix, route, commit, parts, pinned = true) {
  if (parts.length === 0) return { redirect: `${route}/${pinned ? `${commit}/` : ""}` };
  const asset = normalizeAssetPath(parts.join("/"));
  return asset === null ? null : { key: `${prefix}/builds/${commit}/assets/${asset}`, prefix, commit, asset, pinned,
    assetBase: `${route || "/_main"}/${commit}/${asset.slice(0, asset.lastIndexOf("/") + 1)}` };
}

function acceptsGzip(header) {
  let wildcard = false;
  for (const entry of (header ?? "").split(",")) {
    const [encoding, ...parameters] = entry.trim().toLowerCase().split(";");
    const weight = parameters.find(value => value.trim().startsWith("q="));
    const quality = weight ? Number(weight.trim().slice(2)) : 1;
    if (encoding.trim() === "gzip") return quality > 0;
    if (encoding.trim() === "*") wildcard = quality > 0;
  }
  return wildcard;
}

async function fetchPointer(origin, key) {
  const response = await fetch(`${origin}/${key}`, {
    cf: { cacheEverything: true, cacheTtl: 30 },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Build pointer unavailable: ${response.status}`);
  return (await response.text()).trim();
}

function normalizeAssetPath(pathname) {
  let path;
  try {
    path = decodeURIComponent(pathname).replace(/^\/+/, "");
  } catch {
    return null;
  }
  // URL parsers also normalize backslashes. Reject them before constructing
  // the upstream URL, and encode each segment so ? and # stay in filenames.
  if (/[\\\x00-\x1f\x7f]/.test(path) || path.split("/").some((part) => part === ".." || part === ".")) return null;
  if (!path || path.endsWith("/")) path += "index.html";
  return path.split("/").map(encodeURIComponent).join("/");
}

function copyOriginHeaders(headers) {
  const copied = new Headers();
  for (const name of ["range", "if-range", "if-none-match", "if-modified-since"]) {
    const value = headers.get(name);
    if (value) copied.set(name, value);
  }
  return copied;
}

function notFound() {
  return new Response("Web build not found", {
    status: 404,
    headers: { "Cache-Control": "no-store" },
  });
}

function isSlug(value) {
  return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(value ?? "");
}

function isCommit(value) {
  return /^[0-9a-f]{40}$/.test(value ?? "");
}

// Catalog IDs prevent this route becoming an arbitrary URL/credential proxy.
async function avatarAsset(request, url) {
  const headers = new Headers({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "Range, If-Range, If-None-Match, If-Modified-Since",
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, ETag, Last-Modified",
    "Cross-Origin-Resource-Policy": "cross-origin",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
  });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (!["GET", "HEAD"].includes(request.method)) return new Response("Method not allowed", { status: 405, headers });
  const parts = url.pathname.split("/");
  const entry = parts.length === 4 ? avatarById.get(parts[2]) : null;
  const source = entry && (parts[3] === "model" ? entry.url : parts[3] === "thumbnail" ? entry.thumbnail_url : null);
  if (!source) return new Response("Avatar asset not found", { status: 404, headers });
  const upstream = new URL(source);
  const candidates = [upstream.toString()];
  if (upstream.hostname === "arweave.net" && /^\/[A-Za-z0-9_-]{43}$/.test(upstream.pathname)) {
    // The raw endpoint serves the same bytes without a sandbox-subdomain
    // redirect that can reject requests from Workers (including CoolTiger).
    const raw = new URL(upstream);
    raw.pathname = `/raw${upstream.pathname}`;
    candidates.unshift(raw.toString());
  }
  // A gateway can reject a valid CID with 403/429 or go offline. Keep the
  // exact content path when trying another public IPFS gateway.
  if (upstream.pathname.startsWith("/ipfs/")) {
    for (const host of ["ipfs.filebase.io", "ipfs.io", "gateway.pinata.cloud"]) {
      const alternate = new URL(upstream);
      alternate.hostname = host;
      if (!candidates.includes(alternate.toString())) candidates.push(alternate.toString());
    }
  }
  const failures = [];
  for (const target of candidates) {
    let response;
    const originHeaders = copyOriginHeaders(request.headers);
    // Some public storage gateways reject the default Workers user agent.
    originHeaders.set("User-Agent", "Mozilla/5.0 (compatible; GenericVRPlatform/1.0)");
    originHeaders.set("Accept-Encoding", "identity");
    try {
      response = await fetch(target, {
        method: request.method,
        headers: originHeaders,
        redirect: "follow",
        signal: AbortSignal.timeout(parts[3] === "thumbnail" ? 5000 : 15000),
        cf: { cacheEverything: true, cacheTtlByStatus: { "200": 86400, "201-599": -1 } },
      });
    } catch { failures.push("timeout"); continue; }
    if (![200, 206, 304, 416].includes(response.status)) {
      failures.push(String(response.status));
      await response.body?.cancel();
      continue;
    }

    let body = response.body;
    if (parts[3] === "model" && request.method === "GET" && response.status === 200) {
      // Storage gateways often stream chunked responses without Content-Length.
      // A VRM/GLB declares its exact byte length in its first 12 bytes. Use a
      // fixed-length stream so browsers and Godot can report real progress,
      // without buffering the entire model in the Worker.
      const reader = body?.getReader();
      let prefix = new Uint8Array();
      try {
        while (reader && prefix.length < 12) {
          const chunk = await reader.read();
          if (chunk.done) break;
          const combined = new Uint8Array(prefix.length + chunk.value.length);
          combined.set(prefix);
          combined.set(chunk.value, prefix.length);
          prefix = combined;
        }
        const view = new DataView(prefix.buffer, prefix.byteOffset, prefix.byteLength);
        const length = prefix.length >= 12 ? view.getUint32(8, true) : 0;
        if (prefix.length < 12 || view.getUint32(0, true) !== 0x46546c67 || view.getUint32(4, true) !== 2 || length < 20 || length > 64 * 1024 * 1024 || prefix.length > length) {
          await reader?.cancel();
          failures.push("invalid-model");
          continue;
        }
        body = new ReadableStream({
          start(controller) { controller.enqueue(prefix); },
          async pull(controller) {
            const chunk = await reader.read();
            if (chunk.done) controller.close();
            else controller.enqueue(chunk.value);
          },
          cancel(reason) { return reader.cancel(reason); },
        });
        // FixedLengthStream makes Workers preserve Content-Length instead of
        // converting an ordinary ReadableStream to chunked transfer encoding.
        if (typeof FixedLengthStream !== "undefined") body = body.pipeThrough(new FixedLengthStream(length));
        headers.set("Content-Length", String(length));
      } catch {
        await reader?.cancel().catch(() => {});
        failures.push("invalid-model");
        continue;
      }
    }
    for (const name of ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified", "Content-Encoding"]) {
      if (response.headers.has(name) && !(name === "Content-Length" && headers.has(name))) headers.set(name, response.headers.get(name));
    }
    headers.set("Cache-Control", response.status === 416 ? "no-store" : "public, max-age=3600");
    return new Response(request.method === "HEAD" ? null : body, { status: response.status, headers });
  }
  headers.set("X-Avatar-Upstream-Status", failures.join(","));
  return new Response("Avatar storage unavailable. Try again.", { status: 502, headers });
}
