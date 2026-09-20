const APP_HOST = "app.vr.maio-tech.com";
const HOME_HOST = "vr.maio-tech.com";
const API_HOST = "api.vr.maio-tech.com";
const LEGACY_PREVIEW_PREFIX = "/previews/";

export default {
  async fetch(request, env, context) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

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
      if (url.hostname === HOME_HOST) return Response.redirect(`https://${APP_HOST}/`, 302);
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

      const cache = caches.default;
      // Key by the immutable object, not arbitrary caller query parameters.
      const cacheKey = new Request(`https://${APP_HOST}/_cache/${target.key}`);
      const cacheable = request.method === "GET" && !request.headers.has("range");
      if (cacheable) {
        const cached = await cache.match(cacheKey);
        if (cached) return withCachePolicy(cached, target.pinned);
      }

      const originOptions = {
        method: request.method,
        headers: copyOriginHeaders(request.headers),
      };
      let originResponse = await fetch(`${env.ORIGIN_URL}/${target.key}`, originOptions);
      // Keep builds published before versioned storage working during rollout.
      // Only the active legacy build can be served, and never cached as immutable.
      let legacy = false;
      if (originResponse.status === 404) {
        const marker = await fetch(`${env.ORIGIN_URL}/${target.prefix}/builds/${target.commit}/complete.txt`, { method: "HEAD" });
        if (marker.status === 404 && await fetchPointer(env.ORIGIN_URL, `${target.prefix}/commit.txt`) === target.commit) {
          originResponse = await fetch(`${env.ORIGIN_URL}/${target.prefix}/assets/${target.asset}`, originOptions);
          legacy = true;
        }
      }
      if (!originResponse.ok && originResponse.status !== 416) {
        return originResponse.status === 404
          ? notFound()
          : new Response("Build origin unavailable", { status: 502 });
      }

      const headers = new Headers(originResponse.headers);
      headers.set("X-Content-Type-Options", "nosniff");
      headers.set("Cross-Origin-Opener-Policy", "same-origin");
      headers.set("Cross-Origin-Embedder-Policy", "require-corp");
      headers.set("Cache-Control", originResponse.status === 416
        ? "no-store" : "public, max-age=31536000, immutable");
      const response = new Response(request.method === "HEAD" ? null : originResponse.body, {
        status: originResponse.status,
        headers,
      });

      if (cacheable && !legacy && originResponse.status === 200) {
        context.waitUntil(cache.put(cacheKey, response.clone()));
      }
      return originResponse.status === 416 ? response : withCachePolicy(response, target.pinned && !legacy);
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
  return asset === null ? null : { key: `${prefix}/builds/${commit}/assets/${asset}`, prefix, commit, asset, pinned };
}

function withCachePolicy(response, pinned) {
  if (pinned) return response;
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", "public, max-age=0, must-revalidate");
  return new Response(response.body, { status: response.status, headers });
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
  for (const name of ["range", "if-range"]) {
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
