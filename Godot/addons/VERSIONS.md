# Vendored addons

These addons are vendored (copied into the repo) rather than submodules so the
project builds offline and every checkout has exactly the code CI tested.
Binaries (*.so, *.dll, *.dylib, *.aar, *.wasm) are stored in Git LFS, so
clones stay small but still get everything in one fetch.

## Inventory

| Addon | Vendored version | Upstream | Local patches |
| --- | --- | --- | --- |
| godot-xr-tools | 4.5.2 (`plugin.cfg`) | https://github.com/GodotVR/godot-xr-tools | `xr/start_xr.gd` + `xr/start_xr.tscn` (WebXR-first init, `webxr_support_changed`, app-owned `start_webxr` gesture plus the initial-input-source bootstrap in `res://web/webxr_session_bootstrap.js`; upstream EnterVR button removed). The 4.5.1-era `_property_get_revert` hacks were dropped — 4.5.2 fixes them properly |
| godotopenxrvendors | 5.1.0 (`GodotOpenXRVendors_CHANGES.md`) | https://github.com/GodotVR/godot_openxr_vendors | None. Prune per-platform `.bin` binaries for storefronts you never export to |

`twovoip`, `webrtc_native`, and `godobuf` are also vendored here but their
versions are not recorded anywhere yet — add rows with upstream URL and
pinned version before the next upgrade.

## How to upgrade an addon

1. Note the currently vendored version from the table above.
2. Download the pinned upstream release (tag zip, not a branch snapshot) and
   verify its sha256 against the release page.
3. Diff it against `Godot/addons/<name>` **before** copying. The only deltas
   should be the local patches listed above. Any other delta means the
   vendored copy drifted and needs reconciling first.
4. Replace the addon directory, then re-apply each listed local patch. Keep
   the repo's `.import` files unless assets actually changed — restore them
   after copying and let `--editor --import` rewrite only what it needs.
5. Verify: `godot --headless --xr-mode off --editor --import --path Godot`
   with no script errors, then run the suites that touch the addon
   (`movement`, `tracked_hand`, `hand_menu`, lobby, and the full
   `network_test.tscn` against a live server).
6. Update the version in the table above in the same commit as the upgrade.
