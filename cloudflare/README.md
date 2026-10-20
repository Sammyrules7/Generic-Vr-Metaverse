# Web routing

The Worker routes build URLs to Garage, pins relative assets from live HTML to a
single commit, sets the isolation headers Godot needs, and selects precompressed
assets. Immutable origin objects use Cloudflare's `fetch()` cache rather than
`caches.default`. Enable Tiered Cache in the zone if desired; changing the API
used by the Worker does not enable the zone setting itself.

`vr.maio-tech.com` now uses the zone Redirect Rule `vr_home_to_app`, matching
`http.host eq "vr.maio-tech.com"` and returning 302 to
`https://app.vr.maio-tech.com/`. It deliberately preserves the former behavior of
dropping the incoming path and query. Its proxied `192.0.2.1` A record is only a
placeholder: the Redirect Rule handles the request before any origin connection.
The hostname is no longer attached to the Worker or listed in `wrangler.jsonc`.

## API migration

Keep the API binding/proxy until the Gateway changes are deployed. The HTTPRoute
already accepts `api.vr.maio-tech.com`, but an HTTPRoute alone does not configure
TLS. The Servers repository now contains the missing exact-host HTTPS listener,
Cloudflare Origin certificate, and Cloudflare mTLS policy target under
`cluster/infrastructure/ingress/main-setup/`.

1. Reconcile those Servers changes through the existing cluster deployment flow.
   Wait for Certificate `ingress/vr-api-origin-cert` to be Ready, the Gateway to be
   Programmed, and the server HTTPRoute to be Accepted with resolved references.
2. Confirm Cloudflare Authenticated Origin Pulls remains enabled (the zone was
   already enabled during this review),
   as required by the existing `cloudflare-mtls` client-validation policy. Keep
   SSL mode Full (strict); the Cloudflare Origin certificate is trusted by
   Cloudflare, not by ordinary direct clients.
3. Replace the Worker custom domain `api.vr.maio-tech.com` with a proxied CNAME to
   `vr-api-origin.svc.maio-tech.com` (which points to the same Gateway). Keep the
   public Host/SNI `api.vr.maio-tech.com`; no origin host rewrite is needed.
   Restore the Worker custom domain immediately if the following check fails.
4. Verify a real `wss://api.vr.maio-tech.com/ws` upgrade returns 101 and a client
   can join a room. Ordinary HTTP requests to `/ws` return 400 because an upgrade
   is required; that is not enough to verify the migration.
5. Remove the API route and `API_ORIGIN_URL` from `wrangler.jsonc`, then remove
   `API_HOST` and its passthrough block from the Worker. Deploy together so CI
   cannot reattach the removed custom domain on its next run.

The API remains routed through the Worker while these prerequisites are pending.
No Kubernetes context is configured on the development machine, so the Gateway
changes have been rendered locally but not applied.

Legacy `/previews/` redirects and active pre-versioned storage remain supported.
Remove the latter only after all retained active pointers have versioned builds;
otherwise previously published links would stop loading.

Run Worker regressions with `node --test cloudflare/tests/worker.test.mjs`.
These check upstream cache configuration and response behavior, not real CDN hit
rates. Verify production `CF-Cache-Status`/origin traffic after deployment. The
router and current CI changes have not been published from this checkout.
