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
    if (url.hostname === API_HOST) {
      const upstream = new URL(url.pathname + url.search, env.API_ORIGIN_URL);
      return fetch(new Request(upstream, request));
    }
    if (url.hostname === HOME_HOST) return Response.redirect(`https://${APP_HOST}/`, 302);
    if (url.pathname.startsWith(LEGACY_PREVIEW_PREFIX)) {
      url.pathname = url.pathname.slice("/previews".length);
      return Response.redirect(url.toString(), 301);
    }

    try {
      const target = await resolveTarget(url.pathname, env.ORIGIN_URL);
      if (!target) return notFound();
      if (target.previewRoot && !url.pathname.endsWith("/")) {
        url.pathname += "/";
        return Response.redirect(url.toString(), 301);
      }

      const cache = caches.default;
      const cacheUrl = new URL(request.url);
      cacheUrl.searchParams.set("__build", target.commit);
      const cacheKey = new Request(cacheUrl, request);
      const cacheable = target.preview && request.method === "GET" && !request.headers.has("range");
      if (cacheable) {
        const cached = await cache.match(cacheKey);
        if (cached) return withBrowserRevalidation(cached);
      }

      const originUrl = new URL(`${env.ORIGIN_URL}/${target.key}`);
      originUrl.searchParams.set("build", target.commit);
      const originResponse = await fetch(originUrl, {
        headers: copyOriginHeaders(request.headers),
      });
      if (!originResponse.ok) {
        return originResponse.status === 404
          ? notFound()
          : new Response("Build origin unavailable", { status: 502 });
      }

      const headers = new Headers(originResponse.headers);
      headers.set("X-Content-Type-Options", "nosniff");
      setCrossOriginIsolationHeaders(headers);
      headers.set(
        "Cache-Control",
        target.preview
          ? "public, max-age=0, must-revalidate"
          : "public, max-age=0, must-revalidate",
      );
      const response = new Response(request.method === "HEAD" ? null : originResponse.body, {
        status: originResponse.status,
        headers,
      });

      if (cacheable && originResponse.status === 200) {
        const cached = response.clone();
        cached.headers.set("Cache-Control", "public, max-age=3600");
        context.waitUntil(cache.put(cacheKey, cached));
      }
      return response;
    } catch (error) {
      console.error(error);
      return new Response("Unable to load this web build", { status: 500 });
    }
  },
};

async function resolveTarget(pathname, origin) {
  const parts = pathname.replace(/^\/+/, "").split("/");
  const branch = parts[0];
  if (isSlug(branch)) {
    const activeCommit = await fetchPointer(origin, `branches/${branch}/commit.txt`);
    if (isCommit(activeCommit)) {
      parts.shift();
      // A 40-character second segment selects a specific commit. All other
      // paths resolve directly against the branch's latest published assets.
      if (isCommit(parts[0])) {
        const commit = parts.shift();
        if (activeCommit !== commit) return null;
      }
      return {
        key: `branches/${branch}/assets/${normalizeAssetPath(parts.join("/"))}`,
        preview: true,
        previewRoot: parts.length === 0 || parts.every((part) => part === ""),
        commit: activeCommit,
      };
    }
  }

  const commit = await fetchPointer(origin, "channels/main/commit.txt");
  if (!isCommit(commit)) return null;
  return {
    key: `channels/main/assets/${normalizeAssetPath(pathname)}`,
    preview: false,
    previewRoot: false,
    commit,
  };
}

async function fetchPointer(origin, key) {
  const response = await fetch(`${origin}/${key}`, {
    cf: { cacheEverything: true, cacheTtl: 30 },
  });
  return response.ok ? (await response.text()).trim() : null;
}

function normalizeAssetPath(pathname) {
  let path;
  try {
    path = decodeURIComponent(pathname).replace(/^\/+/, "");
  } catch {
    return "index.html";
  }
  if (!path || path.endsWith("/")) path += "index.html";
  if (path.split("/").some((part) => part === ".." || part === ".")) return "index.html";
  return path;
}

function copyOriginHeaders(headers) {
  const copied = new Headers();
  for (const name of ["range"]) {
    const value = headers.get(name);
    if (value) copied.set(name, value);
  }
  return copied;
}

function withBrowserRevalidation(response) {
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", "public, max-age=0, must-revalidate");
  setCrossOriginIsolationHeaders(headers);
  return new Response(response.body, { status: response.status, headers });
}

function setCrossOriginIsolationHeaders(headers) {
  // SharedArrayBuffer, and therefore Godot's threaded Web export, is only
  // available to pages served in a cross-origin isolated browsing context.
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Cross-Origin-Embedder-Policy", "require-corp");
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
