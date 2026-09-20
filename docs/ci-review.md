# Git, file hygiene, and CI follow-up

Reviewed 2026-09-20. These edits build on the earlier code review; neither pass
has been committed or deployed.

## Changes made

| Area | Before | After |
| --- | --- | --- |
| Router edits | Worker/config changes triggered a Godot export, artifact transfer, and publication. | `Worker-deploy.yaml` deploys independently. Game previews no longer redeploy the router. |
| Server edits | Every run selected and pushed seven Nix image closures through seven build invocations. | Server-only pushes select one image. Toolchain changes and manual runs select all seven in one Nix build invocation. |
| Image selection | No distinction between server and toolchain changes. | Compare the complete push with its previous commit, including multi-commit pushes. Unknown history falls back to all images. |
| Image pins | Repeated inline commands; stale push attempts when a branch advanced during the build. | One mapping in `scripts/update_ci_images.sh` updates every consumer. A branch advance skips stale pins with a summary message. |
| Game caches | Keys mostly depended on `project.godot`, remaining constant across asset changes. | Keys include the actual Godot version and built commit, with compatible-version fallback. Web and native caches stay separate. |
| Gradle cache | Keyed from Gradle files absent from the checkout; location relied on home-directory defaults. | Explicit `GRADLE_USER_HOME`, keyed by engine version, `flake.lock`, and export settings. |
| Unnecessary exports | Main-branch server/docs edits triggered native exports. | Native exports respond to game/release inputs. Godot README-only changes do not trigger game exports. |
| Imports | `--editor --quit` used as an import step. | Explicit `--import`, with XR disabled for imports. |
| Checkout | The image builder requested LFS game assets. | LFS downloads retained for game builds, omitted for code/configuration jobs. |
| Tool image | Godot release image included unused AWS CLI and Wrangler. | Removed both; Wrangler remains in the deployment image. |
| Credentials | Build jobs received deployment secrets; most checkouts retained repository credentials. | Secrets scoped to publishing jobs/steps. Only the image-pinning checkout retains Git credentials for its push. |
| Signing | Android key left in workspace and interpolated into shell source. | Environment variable input, restrictive file permissions, and an `always()` cleanup step. |
| Itch launch | The manifest copied into Windows builds only defined Linux. | Added the Windows executable action. |

Existing cache keys cannot be overwritten. The old Godot keys could therefore
repeatedly restore an early snapshot without saving updated imports. The new keys
allow refreshed snapshots while reusing compatible imports. See the
[cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

Artifact actions remain at v3 deliberately. Forgejo documents v3 or its patched
v4; blindly switching to GitHub's current artifact actions risks incompatibility.
See [Forgejo's artifact documentation](https://forgejo.org/docs/v15.0/user/actions/advanced-features/).

## Files and Git

- No orphaned `.uid` or `.import` files were found among tracked files.
- Git LFS is in use: 150 current paths, with pointer validation passing. Keep
  `Godot/.gitattributes` and the hooks. The development shell now includes
  `git-lfs` so the hooks work there too.
- The approximately 254 MiB `.godot` directory is an ignored local cache, not
  committed debris. Clearing it would cause another import, so it was retained.
- The 37 tracked lightmap unwrap caches and Blender/audio authoring sources were
  retained; they support scene preparation/reproduction.
- Worktree pruning in dry-run mode found nothing eligible to prune. Existing
  worktrees and branches were retained.
- Local `main` had no upstream. It now tracks the existing `origin/main` ref;
  no branch tip or history was changed. It remains behind that local remote ref.
  No remote fetch was performed during this review.
- Added ignores for root `.wrangler/` and `node_modules/` output.
- Removed the unused `GODOT_VERSION` workflow variable. The installed engine now
  supplies its own cache version.

## Deployment notes

The router workflow runs for relevant pushes to `main` and `Multiplayer`, and can
be dispatched manually. Other preview branches still publish games using the
shared router. Latest-branch and optional commit URLs are unchanged.

Image references remain pinned. Run **Build Nix images** on the committed changes
to publish the reduced tool image and update references; existing pins were not
replaced with unbuilt local paths. The generated commit retains `[skip ci]`, so
dispatch a client build afterward to exercise a toolchain-only update immediately.
If the branch advances during the image build, rerun on the latest commit to
update skipped pins.

Publication concurrency is best effort. The final Git push can still fail if
another push lands between the branch-head check and push; it will not overwrite
remote work.

## Further optimization worth measuring

1. Record cold/warm timings for checkout/LFS, imports, exports, Gradle, and artifact
   transfer. No runner timing data was available, so no percentage speedup is claimed.
2. If exports dominate and multiple runners are available, run Linux, Windows,
   and Android exports in parallel. This trades elapsed time for repeated checkout,
   import, and cache transfer. The current native exports share one import.
3. Watch storage after switching to commit-specific cache keys; configure eviction
   on the cache service and choose artifact retention periods deliberately.
4. Consider excluding test/authoring resources from exported games after checking
   a full exported build. This pass leaves those files and export rules intact.
5. Branch slug collisions remain possible. Fixing that needs a URL policy change,
   so existing branch URLs were preserved.

## Validation

- ShellCheck and Actionlint passed, excluding expected custom-runner labels and
  the GitHub-specific artifact-v3 warning.
- Isolated checks exercised server/all selection, multi-commit toolchain pushes,
  manual runs, new branches, and missing-history fallback.
- Mocked Nix/Attic checks verified batched builds, arbitrary output ordering,
  both publisher/router pins, server-only edits, and failure handling.
- Changed Nix image derivations and the development shell evaluated successfully.
- LFS pointer validation, orphan metadata checks, worktree prune dry-run, and
  `git diff --check` passed.

No existing game/server test suites, full platform exports, remote workflows,
Attic uploads, router deployments, or releases were run in this pass.
