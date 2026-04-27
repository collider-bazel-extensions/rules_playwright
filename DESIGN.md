# rules_playwright — design decisions

All decisions inherited from `collider-bazel-extensions/rules_pg`,
`rules_temporal`, `rules_kind`. Where the three diverged, we follow the
majority. Anything Playwright-specific is flagged.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Both.** `MODULE.bazel` primary; `repositories.bzl` mirror for legacy. | All three |
| 2 | Module extension shape | Two tag classes: `version` (download) + `system` (host-installed). Hub repo name `playwright_<ver_underscored>_<plat>`. | All three |
| 3 | Toolchain type | `PLAYWRIGHT_TOOLCHAIN_TYPE = Label("//toolchain:playwright")`. `ToolchainInfo(playwright=binary_info)`. | rules_pg, rules_temporal (rules_kind uses string form — minority) |
| 4 | Binary provisioning | Hand-maintained `PLAYWRIGHT_VERSIONS` dict keyed `{ver: {bundles: [{name, revision, platforms: {plat: {url, sha256, strip_prefix}}}]}}`. One Playwright "browser type" (chromium) maps to multiple bundles (chromium + chromium_headless_shell, +ffmpeg if recording video) — see `BROWSER_TYPE_BUNDLES`. Each bundle is extracted into a `<name>-<revision>/` subdir and laid into runfiles under `browsers/<name>-<revision>/` so `PLAYWRIGHT_BROWSERS_PATH` can point at one root. Refresh via `tools/update_checksums.sh`. | rules_pg pattern, schema extended |
| 5 | Public surface | `playwright_binary`, `playwright_test`, `playwright_server`, `playwright_health_check` + `PlaywrightBinaryInfo`, `PlaywrightBrowserInfo`. | All three (`_test` per pg/temporal; `_server` + `_health_check` per all) |
| 6 | rules_itest integration | Emit `playwright_server` + `playwright_health_check` as standalone targets that drop into `itest_service.exe` / `.health_check`. **No pass-through `services=` attr** — composition is the consumer's job. | All three |
| 7 | rules_oci | **Not a dep.** Document image-bundled-browser pattern but don't mandate it. | All three |
| 8 | Platform matrix v1 | `linux_amd64`, `darwin_arm64`, `darwin_amd64`. No `linux_arm64`, no Windows. | All three |
| 9 | Repo layout | Flat: `/{MODULE.bazel,WORKSPACE,defs.bzl,extensions.bzl,repositories.bzl}`, `/private/`, `/toolchain/`, `/tests/`, `/tools/`, **plus `/examples/`** (deliberate divergence from rules_pg/temporal/kind — Playwright's composition story is busy enough that smoke tests aren't enough; full runnable compositions with itest/kind live under `examples/`). | All three + intentional break |
| 10 | MODULE deps | `bazel_skylib 1.5.0`, `platforms 0.0.9`. **No `aspect_rules_js`, no `rules_oci`, no `rules_itest`** (consumer adds itest themselves). | All three |
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
| MODULE + WORKSPACE | wired |
| Module extension (`version` + `system`) | wired |
| Hub + per-bundle child repos with real `download_and_extract` | wired |
| Pinned chromium 1.49.0 sha256s for linux_amd64, darwin_amd64, darwin_arm64 | wired |
| `tools/update_checksums.{sh,py}` (fetches browsers.json, sha256s, regenerates manifest) | wired |
| `playwright_test`, `_server`, `_binary`, `_health_check` rules | wired |
| `launcher.py` (env, exec, SIGTERM forwarding) | wired |
| Analysis tests (executable presence) | wired |
| Real `tests/smoke.spec.ts` + `playwright.config.ts` | wired |
| End-to-end `bazel test //tests:smoke_test` execution | **green** (chromium 1.49 headless via assembled `browsers/` runfiles tree) |
| node_modules wiring (`@playwright/test`) | consumer's responsibility; `tests/` ships a `:node_modules` filegroup over a host `npm install` for the smoke test |

## Deferred (not v0.1.0)

- Firefox + webkit channels (table extension + new exec paths in `versions.bzl`).
- Trace/screenshot/video as declared outputs (currently rely on `TEST_UNDECLARED_OUTPUTS_DIR`).
- Branded `chrome` / `msedge` channels (license review).
- Headed-mode debug target (`bazel run :smoke_test.debug`).
- `linux_arm64` and Windows.
- Bundled node toolchain (currently relies on host `npx`).
