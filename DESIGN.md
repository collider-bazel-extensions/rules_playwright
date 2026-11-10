# rules_playwright — design decisions

All decisions inherited from `collider-bazel-extensions/rules_pg`,
`rules_temporal`, `rules_kind`. Where the three diverged, we follow the
majority. Anything Playwright-specific is flagged.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod only at v0.1.** `repositories.bzl` exists but exports no top-level setup macros. WORKSPACE support deferred. | Divergence from siblings — none of our consumers need legacy WORKSPACE |
| 2 | Module extension shape | Two tag classes: `version` (download) + `system` (host-installed). Hub repo name `playwright_<ver_underscored>_<plat>`. | All three |
| 3 | Toolchain type | `PLAYWRIGHT_TOOLCHAIN_TYPE = Label("//toolchain:playwright")`. `ToolchainInfo(playwright=binary_info)`. | rules_pg, rules_temporal (rules_kind uses string form — minority) |
| 4 | Binary provisioning | Hand-maintained `PLAYWRIGHT_VERSIONS` dict keyed `{ver: {bundles: [{name, revision, platforms: {plat: {url, sha256, strip_prefix}}}]}}`. One Playwright "browser type" (chromium) maps to multiple bundles (chromium + chromium_headless_shell, +ffmpeg if recording video) — see `BROWSER_TYPE_BUNDLES`. Each bundle is extracted into a `<name>-<revision>/` subdir and laid into runfiles under `browsers/<name>-<revision>/` so `PLAYWRIGHT_BROWSERS_PATH` can point at one root. Refresh via `tools/update_checksums.sh`. | rules_pg pattern, schema extended |
| 5 | Public surface | `playwright_binary`, `playwright_test`, `playwright_server`, `playwright_health_check` + `PlaywrightBinaryInfo`, `PlaywrightBundleInfo`. | All three (`_test` per pg/temporal; `_server` + `_health_check` per all). Bundle-shaped provider replaces the original `PlaywrightBrowserInfo` because Playwright's chromium browser type pulls multiple bundles. |
| 6 | rules_itest integration | Emit `playwright_server` + `playwright_health_check` as standalone targets that drop into `itest_service.exe` / `.health_check`. **No pass-through `services=` attr** — composition is the consumer's job. | All three |
| 7 | rules_oci | **Not a dep.** Document image-bundled-browser pattern but don't mandate it. | All three |
| 8 | Platform matrix v1 | `linux_amd64`, `darwin_arm64`, `darwin_amd64`. No `linux_arm64`, no Windows. | All three |
| 9 | Repo layout | Flat: `/{MODULE.bazel,WORKSPACE,defs.bzl,extensions.bzl,repositories.bzl}`, `/private/`, `/toolchain/`, `/tests/`, `/tools/`, **plus `/examples/`** (deliberate divergence from rules_pg/temporal/kind — Playwright's composition story is busy enough that smoke tests aren't enough; full runnable compositions with itest/kind live under `examples/`). | All three + intentional break |
| 10 | MODULE deps (consumer-visible) | `bazel_skylib`, `platforms`, `rules_python`, and since v0.3.0 `rules_nodejs` (node comes from its runtime toolchain). **No `aspect_rules_js`, no `rules_oci`, no `rules_itest`** in the consumer-visible graph. `aspect_rules_js`, `rules_itest`, and `rules_shell` are present as `dev_dependency = True` for the in-tree smoke + itest examples only — consumers do not inherit them. | All four + dev-dep carve-out |
| 11 | Default test tags | `["playwright"]`; internal wrapper rules tagged `manual`. Playwright-specific: also `["requires-network", "no-sandbox"]` because Chromium's sandbox conflicts with Bazel's. | rules_pg pattern + rules_kind's `no-sandbox` precedent |
| 12 | Naming | snake_case rules, `MixedCaseInfo` providers, `UPPER_SNAKE` constants, `_underscored` private aliases in `defs.bzl`. | All three |
| 13 | Update workflow | `tools/update_checksums.sh <version>...` reads `playwright-core/browsers.json`, downloads each bundle, rewrites the manifest in place. | rules_pg |
| 14 | Runtime lifecycle | One Python `private/launcher.py` per ruleset, owns env setup, exec, SIGTERM forwarding. | All three |
| 15 | Sharding | Bazel `shard_count` only at v1; defer Playwright `--shard` integration. | (No precedent — minimal default) |

## Playwright-specific notes

- `playwright_server` corresponds to `npx playwright run-server` (browser-as-a-service WS endpoint), not the test runner. The test runner is one-shot via `playwright_test`.
- `PLAYWRIGHT_BROWSERS_PATH` is set by `launcher.py` so Playwright never touches `~/.cache/ms-playwright`.
- Chromium needs `/dev/shm`. Mount or run with `--ipc=host` if running tests inside an OCI container; flagged in launcher.py docs only.

## v0.1.0 status

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | wired |
| Module extension (`version` + `system`) | wired |
| Hub + per-bundle child repos with real `download_and_extract` | wired |
| Pinned chromium + chromium_headless_shell 1.49.0 sha256s for linux_amd64, darwin_amd64, darwin_arm64 | wired |
| `tools/update_checksums.py` (fetches browsers.json, sha256s, regenerates manifest) — dogfooded, regenerates bit-identical | wired |
| `playwright_test`, `_server`, `_binary`, `_health_check` rules | `_test`, `_server`, and `_binary` runtime-validated. `_health_check` analysis-only — its runtime test would need a wrapper to inject a synthesized `PLAYWRIGHT_SERVER_URL` from a TCP listener; deferred. `_server`'s port is now resolved at runtime via `$PORT` (overriding the build-time `port` attr), composing cleanly with `itest_service.autoassign_port`. |
| `launcher.py` (env, exec, SIGTERM forwarding, hardlink-stage spec dir, browsers-path) | wired |
| Analysis tests + version drift guard | wired |
| Real `tests/smoke.spec.ts` + `playwright.config.ts` | wired |
| End-to-end `bazel test //tests:smoke_test` execution | **green** (chromium 1.49 headless via assembled `browsers/` runfiles tree, linux_amd64 only) |
| Examples (`//examples/basic`, `//examples/itest`) executing under `bazel test` | green; `//examples/kind` documentation-only (rules_kind not in BCR, requires Docker) |
| node_modules wiring (`@playwright/test`) | consumer's choice. The in-tree smoke + examples use aspect_rules_js (`//:node_modules/@playwright/test`); README documents both that and a manual `glob(["node_modules/**"])` filegroup pattern as Option B. |
| macOS validation | **outstanding — bundles pinned but never executed against** |

## v0.2.0

| # | Decision | Choice |
|---|---|---|
| 16 | Firefox + webkit channels | **Wired.** `WANTED_BUNDLES` extended to `["chromium", "chromium-headless-shell", "firefox", "webkit"]`; `BROWSER_TYPE_BUNDLES` adds `firefox` → `["firefox"]` and `webkit` → `["webkit"]`. Linux pin: firefox/webkit ubuntu-22.04 variants (chromium ships a generic linux build). macOS pin: webkit `mac-14` (Sonoma) — webkit ships per-macOS-major builds, no generic mac variant. Non-22.04 / non-mac-14 consumers should fall back to `playwright.system()`. |
| 17 | Multi-browser BUILD-level matrix | `playwright_test(browsers = [...])` with more than one entry fans out into N `_playwright_test` rule instances named `<name>_<browser>` plus a `test_suite` named `<name>`. Each per-browser target carries the browser literal as a tag for CI matrix selection (`--test_tag_filters=-webkit`). Consumer `playwright.config.ts` must declare a `projects:` entry per browser whose `name` matches the literal — the launcher passes `--project=<browser>` to `playwright test`. Single-browser callers (`browsers = ["chromium"]`, default) get the v0.1 behaviour plus a `chromium` tag — no rename. |

## v0.2.1

- **Extension: per repo name, root's tag else rules_playwright's own.** The extension runs once for the whole build and sees every module's tags. rules_playwright's own `MODULE.bazel` declares `@playwright` and registers `@playwright//:all` for every consumer, but through v0.2.0 only the root's tags counted (`if not mod.is_root: continue`, against a collision the extension itself caused by creating a name twice), so a root without `playwright.version()` failed to resolve. Now each name is created once: the root's declaration wins, else rules_playwright's. Identical repeats are fine; one name declared two different ways in a module, or an unsupported version, fails naming the tag.
- **Release archive:** `tests/` and `examples/` are `export-ignore` (`.gitattributes`); they load dev-only modules. Since v0.3.1 this repo's own npm workspace (`package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, and the `npm_link_all_packages` that loads the dev-only `@npm`) lives in `dev/`, also `export-ignore`, instead of the root package, so `@rules_playwright//...` loads for consumers; in-tree targets use `//dev:node_modules/@playwright/test`. CI's consumer job queries `//...` from the commit's `git archive`.
- **Name clash with the BCR:** the BCR's `rules_playwright` (mrmeku/rules_playwright; 0.2.1 to 0.5.3, including 0.3.0) is a different project. Bzlmod resolves one module per name, so consumers must override (`archive_override` / `git_override`) or get the BCR's module, the two can't share a build, and this module can't go to the BCR under this name. Renaming was considered and not done (2026-11-10); the README documents the clash.
- **Node from rules_nodejs (v0.3.0, rules_playwright#4):** `playwright_test`, `playwright_server` and `playwright_binary` resolve `@rules_nodejs//nodejs:runtime_toolchain_type` (the target platform's node), put its `node` in runfiles and pass it to launcher.py as `--node`; the launcher no longer reads `$PATH`. rules_nodejs is a light, BCR-hosted dependency and registers a default node for every module, so consumers need no wiring; rules_js stays out of the consumer graph, and `@playwright/test` still comes from the consumer's own `data`. Fetching `@playwright/test` ourselves was the alternative, rejected: rules_js users expect the runner from their lockfile.
- **`@playwright/test` version check:** a validation action (`private/version_check.py`, wired through `OutputGroupInfo(_validation = ...)`) finds `@playwright/test/package.json` in `data` (rules_js packages are directory artifacts, walked with symlinks followed) and fails the build unless its version equals the toolchain's `PlaywrightBinaryInfo.version`. A validation action, not a test-time check, so a mismatch fails `bazel build` and doesn't need a browser. `system` mode is skipped (its version is `"system"`). `//tests/version_check:{match,mismatch}` exercise it on fixture packages; CI asserts `mismatch` fails to build.
- **CI `consumer` job** (`.github/consumer/check.sh`) runs rules_playwright as a dependency from the commit's `git archive`: untagged root resolves and the hub toolchain is 1.49.0, repeated tag resolves, unsupported version and a version/system conflict fail clearly, `//private/...` and `//toolchain/...` load.

## Deferred (not v0.2.0)

- Trace/screenshot/video as declared outputs (currently rely on `TEST_UNDECLARED_OUTPUTS_DIR`).
- Branded `chrome` / `msedge` channels (license review).
- Headed-mode debug target (`bazel run :smoke_test.debug`).
- `linux_arm64` and Windows.
- Multi-browser `playwright_server` (`run-server` is one-process-per-browser; single-browser only at v0.2).
- Wildcard `browsers = ["all"]`. Explicit list only — keeps BUILD changes loud when chrome/msedge channels are added.
