# rules_playwright

Hermetic [Playwright](https://playwright.dev) UI tests for Bazel. Each
`playwright_test` target gets a pinned, sha256-verified Chromium binary fetched
by Bazel, never by Playwright at runtime. Composes with
[`rules_itest`](https://github.com/dzbarsky/rules_itest) for service-dependent
end-to-end tests and with
[`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind) for
in-cluster smokes.

**Supported platforms (v0.1):** Linux (x86\_64). macOS (arm64, x86\_64) bundles
are pinned but **validation is pending** — see
[Contributing → Help wanted: macOS validation](#help-wanted-macos-validation).
**Supported Playwright versions:** 1.49
**Supported browsers (v0.1):** Chromium

> **Note on hermeticity.** Browsers are fully pinned. Node, `npx`, and the
> `@playwright/test` runner are **not** vendored — see
> [Hermeticity exceptions](#hermeticity-exceptions) before depending on this
> for production CI.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [playwright\_test](#playwright_test)
  - [playwright\_server](#playwright_server)
  - [playwright\_health\_check](#playwright_health_check)
  - [playwright\_binary](#playwright_binary)
- [`rules_itest` integration](#rules_itest-integration)
- [`rules_kind` integration](#rules_kind-integration)
- [Providers](#providers)
- [Environment variables injected by `playwright_test`](#environment-variables-injected-by-playwright_test)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Toolchain integration](#toolchain-integration)
- [Examples](#examples)
- [FAQ](#faq)
- [Contributing](#contributing)

---

## Installation

### Bzlmod (MODULE.bazel)

```python
bazel_dep(name = "rules_playwright", version = "0.1.0")

playwright = use_extension("@rules_playwright//:extensions.bzl", "playwright")
playwright.version(version = "1.49.0")
use_repo(playwright, "playwright")
```

To use the host-installed `npx` instead of fetching a hermetic browser bundle
(faster setup, sacrifices hermeticity):

```python
playwright.system(name = "playwright")
use_repo(playwright, "playwright")
```

### Legacy WORKSPACE

`rules_playwright` is **Bzlmod-only** in v0.1. The `WORKSPACE` mode is not
supported — `repositories.bzl` does not export top-level setup macros.

---

## Quickstart

**1.** Ensure your workspace can deliver `node_modules/@playwright/test` into
the test target's runfiles. `rules_playwright` does not vendor the runner —
you control how it gets there. Two supported patterns:

**Option A — `aspect_rules_js` (recommended).** If you already use rules_js,
just pass the linked target via `data`:

```python
playwright_test(
    name = "smoke_test",
    srcs = ["smoke.spec.ts"],
    config = "playwright.config.ts",
    data = ["//:node_modules/@playwright/test"],
)
```

This is what `rules_playwright`'s own [`tests/smoke_test`](tests/BUILD.bazel)
uses — see the workspace-root `package.json`, `pnpm-lock.yaml`, and
`pnpm-workspace.yaml` for the minimal setup.

**Option B — manual `node_modules` filegroup.** If you don't use rules_js,
keep a `package.json` next to your specs and run `npm install` once. Expose
`node_modules` to Bazel via `glob`:

```python
filegroup(
    name = "node_modules",
    srcs = glob(["node_modules/**"], allow_empty = True),
)

playwright_test(
    name = "smoke_test",
    srcs = ["smoke.spec.ts"],
    config = "playwright.config.ts",
    data = [":node_modules"],
)
```

Pin `@playwright/test` to the same version as the Bazel-fetched browser bundle
(see [Hermeticity exceptions](#hermeticity-exceptions)) regardless of which
option you pick.

**2.** Add a `playwright.config.ts` next to your specs:

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:8080",
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],
});
```

**3.** Declare the test in `BUILD.bazel`:

```python
load("@rules_playwright//:defs.bzl", "playwright_test")

playwright_test(
    name = "smoke_test",
    srcs = ["smoke.spec.ts"],
    config = "playwright.config.ts",
    data = ["//:node_modules/@playwright/test"],
)
```

**4.** Run:

```
bazel test //path/to:smoke_test
```

---

## Rules

### `playwright_test`

```python
load("@rules_playwright//:defs.bzl", "playwright_test")

playwright_test(
    name = "smoke_test",
    srcs = ["smoke.spec.ts"],
    config = "playwright.config.ts",
    browsers = ["chromium"],
    data = ["//:node_modules/@playwright/test"],
)
```

Runs `npx playwright test` against the resolved hermetic browser. The test
launcher sets `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` and
`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` so Playwright never fetches its own copy.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `srcs` | `label_list` | required | Spec files (`.spec.ts`, `.test.ts`, `.spec.js`, `.test.js`). |
| `config` | `label` | `None` | Optional `playwright.config.ts`. If unset, Playwright applies its own discovery. |
| `data` | `label_list` | `[]` | Extra runfiles. **Must include `node_modules/@playwright/test`.** |
| `browsers` | `string_list` | `["chromium"]` | Browser channels. v0.1 supports `chromium` only. |
| `tags` | `string_list` | `[]` | Always merged with `["playwright", "requires-network", "no-sandbox"]`. |

The merged tags are non-negotiable in v0.1 because:

- `requires-network`: Most UI tests hit a service over the network. Override
  by passing `tags = ["playwright", "no-sandbox"]` if your test is fully offline.
- `no-sandbox`: Bazel's sandbox conflicts with Chromium's user-namespace
  sandbox. The browser is launched with `--no-sandbox` regardless.

---

### `playwright_server`

```python
load("@rules_playwright//:defs.bzl", "playwright_server")

playwright_server(
    name = "browsers",
    data = ["//:node_modules/@playwright/test"],
)
```

Long-running `npx playwright run-server`. Drops directly into
`itest_service.exe`. Companion: [`playwright_health_check`](#playwright_health_check).
Use this when you want a single browser daemon shared across multiple tests
in a service group.

The listen port is taken (in priority order) from `$PORT` at runtime, then
the build-time `port` attr. Setting `$PORT` lets the rule compose with
`itest_service.autoassign_port` — see the
[`rules_itest` integration](#rules_itest-integration) example.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `port` | `int` | `0` | Build-time default port; `0` lets Playwright pick. Overridden at runtime by `$PORT` if set (e.g. via `itest_service.env = {"PORT": port(":svc")}`). |
| `data` | `label_list` | `[]` | Extra runfiles. **Must include `node_modules/@playwright/test`.** |
| `browsers` | `string_list` | `["chromium"]` | Browser bundles to assemble in runfiles. v0.1 supports `"chromium"` only. |

---

### `playwright_health_check`

```python
load("@rules_playwright//:defs.bzl", "playwright_health_check")

playwright_health_check(
    name = "browsers_health",
    endpoint_env = "PLAYWRIGHT_SERVER_URL",
)
```

One-shot TCP probe of a `playwright_server`'s WS endpoint. Exits 0 when
reachable, non-zero otherwise. `rules_itest` retries until success or timeout.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `endpoint_env` | `string` | `"PLAYWRIGHT_SERVER_URL"` | Env var holding the `ws://host:port` URL. |

---

### `playwright_binary`

```python
load("@rules_playwright//:defs.bzl", "playwright_binary")

playwright_binary(
    name = "playwright",
    data = ["//:node_modules/@playwright/test"],
)
```

`bazel run //path:playwright -- <args>` invokes `node @playwright/test/cli.js <args>`.
Useful for ad-hoc operations:

```
bazel run //tools:playwright -- show-trace path/to/trace.zip
bazel run //tools:playwright -- codegen http://localhost:8080
```

Browser bundles are deliberately *not* attached — most ad-hoc invocations
(`show-trace`, `codegen` against arbitrary URLs, `--help`) don't need them.
Targets that *do* need a hermetic browser should use `playwright_test` or
`playwright_server` instead.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `data` | `label_list` | `[]` | Extra runfiles. **Must include `node_modules/@playwright/test`.** |

---

## `rules_itest` integration

[`rules_itest`](https://github.com/dzbarsky/rules_itest) models a test run as:
start services in dependency order → run test → stop services.
`rules_playwright` integrates by emitting `*_server` and `*_health_check`
targets that drop into `itest_service`. **There is no pass-through `services =`
attribute** — composition is the consumer's job, matching the rules_pg /
rules_temporal / rules_kind convention.

### Installation

```python
bazel_dep(name = "rules_itest", version = "0.0.21")
```

### Example: Playwright test against a fake app

```python
load("@rules_playwright//:defs.bzl", "playwright_test")
load("@rules_itest//:itest.bzl", "itest_service", "port", "service_test")

# Long-running app under test. itest assigns a free port via autoassign_port
# and exports it to the service via env interpolation.
itest_service(
    name = "app",
    exe = "//myapp:server_bin",
    autoassign_port = True,
    env = {"PORT": port(":app")},
    health_check = "//myapp:server_health",
)

# The Playwright test target itself; `manual` so only `service_test` runs it.
playwright_test(
    name = "ui_test_bin",
    srcs = ["ui.spec.ts"],
    config = "playwright.config.ts",
    data = ["//:node_modules/@playwright/test"],
    tags = ["manual"],
)

# Compose: itest brings :app up, gates on its health_check, then exports
# `PORT_app` into the test process's env. The test's playwright.config.ts
# reads `process.env.PORT_app` to construct `baseURL`.
service_test(
    name = "ui_test",
    services = [":app"],
    env = {"PORT_app": port(":app")},
    test = ":ui_test_bin",
)
```

Env injection is **not automatic** — `service_test(env = {...})` is the
explicit hook. The matching playwright.config.ts:

```typescript
import { defineConfig } from "@playwright/test";
const port = process.env.PORT_app;
if (!port) throw new Error("PORT_app not set — is this running under service_test?");
export default defineConfig({
  use: { baseURL: `http://127.0.0.1:${port}` },
  // …
});
```

### Example: Playwright server as a long-running browser daemon

```python
load("@rules_playwright//:defs.bzl", "playwright_server")
load("@rules_itest//:itest.bzl", "itest_service", "port")

playwright_server(
    name = "browsers",
    data = ["//:node_modules/@playwright/test"],
)

# The launcher reads $PORT at runtime and binds it. itest's autoassign_port
# fills $PORT in via the env interpolation below.
itest_service(
    name = "browsers_svc",
    exe = ":browsers",
    autoassign_port = True,
    env = {"PORT": port(":browsers_svc")},
)
```

Tests that depend on `:browsers_svc` get a hermetic Playwright WS endpoint at
`ws://127.0.0.1:$${//path/to:browsers_svc}/`.

---

## `rules_kind` integration

For end-to-end tests that exercise a real Kubernetes deployment, layer
[`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind) under
`rules_itest`. The kind cluster is a service; the app deployment is a service;
the Playwright test runs once both are healthy.

```python
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_playwright//:defs.bzl", "playwright_test")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")

kind_cluster(name = "cluster", config = "kind-config.yaml")
kind_health_check(name = "cluster_health", cluster = ":cluster")

itest_service(
    name = "k8s",
    exe = ":cluster",
    health_check = ":cluster_health",
)

# Apply manifests after the cluster is healthy. Use any sh_binary that wraps
# `kubectl apply -f ...` — itest will keep it alive long enough to deploy.
itest_service(
    name = "app_deploy",
    exe = "//deploy:apply",
    deps = [":k8s"],
    health_check = "//deploy:ready",
)

playwright_test(
    name = "e2e_bin",
    srcs = ["e2e.spec.ts"],
    config = "playwright.config.ts",
    data = ["//:node_modules/@playwright/test"],
    tags = ["manual"],
)

service_test(
    name = "e2e",
    services = [":app_deploy"],
    test = ":e2e_bin",
)
```

See [`examples/kind/`](examples/kind) for a runnable version with a real
ingress and port-forward shim.

---

## Providers

### `PlaywrightBinaryInfo`

| Field | Type | Description |
|---|---|---|
| `version` | `string` | Playwright version, e.g. `"1.49.0"` |
| `executable` | `File` | The `npx` (or vendored launcher) used to invoke `playwright` |
| `node` | `File` or `None` | Bundled node binary if any (`None` in v0.1) |
| `runfiles` | `depset[File]` | All files required at runtime |

### `PlaywrightBundleInfo`

A single Playwright cache bundle (e.g. `chromium-1148`, `chromium_headless_shell-1148`,
`ffmpeg-1011`). One bundle == one directory under `PLAYWRIGHT_BROWSERS_PATH`.
The `chromium` browser type is delivered as multiple bundles — see
`BROWSER_TYPE_BUNDLES` in `private/versions.bzl`.

| Field | Type | Description |
|---|---|---|
| `name` | `string` | Bundle name as Playwright knows it (e.g. `"chromium"`, `"chromium_headless_shell"`) |
| `revision` | `string` | Revision string (e.g. `"1148"`) |
| `dir_name` | `string` | `"<name>-<revision>"` — the directory name Playwright expects under `PLAYWRIGHT_BROWSERS_PATH` |
| `files` | `depset[File]` | Every file inside the bundle dir (libs, resources, the binary itself) |
| `root` | `File` | A marker file at the bundle dir's root, used to derive runfiles short_path |

---

## Environment variables injected by `playwright_test`

The launcher sets these in the test process before `exec`'ing `npx playwright`:

| Variable | Example | Description |
|---|---|---|
| `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` | `<runfiles>/playwright_chromium_linux_amd64/.../chrome-linux/chrome` | Resolved path to the Bazel-fetched chromium binary. Playwright uses this verbatim instead of looking in `~/.cache/ms-playwright`. |
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | `1` | Belt-and-braces: prevents Playwright from auto-downloading even if the path above is wrong. |
| `HOME` | `$TEST_TMPDIR` | Forces any cache writes into Bazel's per-test scratch dir. |

Variables you set on `playwright_test`'s `env =` attribute, or that
`rules_itest` exports from a service, take precedence — the launcher only sets
the three above and forwards everything else.

---

## Hermeticity exceptions

`rules_playwright` is **partially hermetic**. The browser binary itself is
fully pinned and Bazel-fetched. Several other runtime dependencies are not.
Read this section carefully before depending on it for reproducible CI.

### Not vendored — must be present on the host

| Dependency | Why it's host-resolved | Risk |
|---|---|---|
| `node` (Node.js runtime) | v0.1 deliberately avoids `aspect_rules_js` to keep the dep graph minimal. The launcher invokes `npx` from `$PATH`. | Different Node major versions can change Playwright's behavior. Pin via your CI image. |
| `npx` | Same as above. | Same as above. |
| `@playwright/test` (the test runner JS code) | Must be in the test target's runfiles via `data = [...]`. We do not download the npm package ourselves. | Mismatch between the npm-installed runner version and the Bazel-pinned browser revision causes Playwright to attempt re-download (suppressed by `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, but tests may fail with version-incompatibility errors). Keep them in sync. |
| Shared libraries the browser needs (`libnss3`, `libatk`, `libcups2`, `libxkbcommon0`, `libgbm1`, `libasound2`, …) | Bundling a sysroot is a large undertaking deferred from v0.1. The browser binary is dynamically linked against the host's glibc + GTK stack. | Test passes on developer laptop, fails on slim CI image. The fix is to use a CI image with the libs preinstalled (e.g. `mcr.microsoft.com/playwright`). |
| `/dev/shm` | Chromium needs a writable `/dev/shm` of meaningful size. | Container runtimes default `/dev/shm` to 64 MB; complex pages OOM. Pass `--ipc=host` to docker, or mount a larger tmpfs. |

### Sandbox interaction

`playwright_test` defaults to **`tags = ["playwright", "requires-network",
"no-sandbox"]`**:

- **`no-sandbox`** disables Bazel's sandbox for the test action. Bazel's
  sandbox uses Linux user namespaces and seccomp filters that conflict with
  Chromium's own user-namespace sandbox. The cleanest fix is to disable the
  outer sandbox; the launcher additionally passes `--no-sandbox` to Chromium
  itself.
- **`requires-network`** is on by default because the typical UI test hits a
  service. Override to `["playwright", "no-sandbox"]` if your test is offline
  (e.g. `data:` URLs only).

### What this means in practice

- **`bazel test` on a developer machine with Playwright already installed:** works.
- **`bazel test` on a CI runner using `mcr.microsoft.com/playwright`:** works.
- **`bazel test` on a minimal Alpine or distroless image:** fails until you
  install the missing system libraries.
- **`bazel test` with `--remote_executor` against an arbitrary RBE pool:**
  works only if the RBE platform image carries the required libs and a
  writable `/dev/shm`.

If you need full hermeticity, the supported pattern is to run tests inside an
OCI image (built with `rules_oci`) that bakes the libs in. v0.2 may ship a
`playwright_oci_test` macro for this; for now you compose it yourself.

---

## Toolchain integration

`rules_playwright` exposes a Bazel toolchain at `//toolchain:playwright`. You
typically don't need to touch this — `playwright_test` resolves it
automatically. Use it when writing custom rules that consume Playwright
internals.

```python
load("@rules_playwright//toolchain:toolchain.bzl", "PLAYWRIGHT_TOOLCHAIN_TYPE")

def _my_rule_impl(ctx):
    tc = ctx.toolchains[str(PLAYWRIGHT_TOOLCHAIN_TYPE)]
    chromium = tc.browsers["chromium"]  # PlaywrightBrowserInfo
    # ... use chromium.executable, chromium.runfiles ...

my_rule = rule(
    implementation = _my_rule_impl,
    toolchains = [str(PLAYWRIGHT_TOOLCHAIN_TYPE)],
)
```

---

## Examples

End-to-end runnable examples live in [`examples/`](examples/). Each is a
self-contained Bazel package you can copy into your own repo:

| Path | What it shows |
|---|---|
| [`examples/basic`](examples/basic) | Smallest possible `playwright_test` against a `data:` URL. No services. |
| [`examples/itest`](examples/itest) | `playwright_test` driving a fake HTTP service spun up by `rules_itest`. |
| [`examples/kind`](examples/kind) | `playwright_test` driving an app deployed into a `rules_kind` cluster. |

Run any example with:

```
bazel test //examples/basic:smoke_test
bazel test //examples/itest:ui_test
bazel test //examples/kind:e2e
```

---

## FAQ

**Q: Why isn't `@playwright/test` vendored alongside the browser?**

The npm package is universal (pure JS). Vendoring it would force a hard
dependency on `aspect_rules_js`, which the rules_pg/temporal/kind convention
explicitly avoids. Consumers of this ruleset already have a JS toolchain story;
we plug into theirs.

---

**Q: Can I use a different version of Playwright than the pinned table?**

Yes — register multiple versions:

```python
playwright.version(name = "playwright_1_48", version = "1.48.0")
playwright.version(name = "playwright_1_49", version = "1.49.0")
use_repo(playwright, "playwright_1_48", "playwright_1_49")
```

…then reference the toolchain you want via `--extra_toolchains` or
`register_toolchains`. To add a version that's not in the manifest, run
`bash tools/update_checksums.sh <version>` first.

---

**Q: Firefox? WebKit?**

Deferred to v0.2. The download tool already knows how to fetch them; the
toolchain rule needs new exec-path handling for each channel.

---

**Q: Linux arm64? Windows?**

Deferred. The download tool would need new platform tuples and matching
constraint mappings. PRs welcome.

---

**Q: How do I update sha256s when a new Playwright version ships?**

```
bash tools/update_checksums.sh 1.50.0
```

It downloads `playwright-core@<version>` from npm, reads `browsers.json`,
fetches each platform's chromium bundle, computes sha256, and rewrites
`private/versions.bzl` in place.

---

**Q: My test prints `Failed to launch browser: ... missing libnss3.so`.**

Host system libraries aren't vendored — see
[Hermeticity exceptions](#hermeticity-exceptions). Either run on
`mcr.microsoft.com/playwright` or `apt install libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libxkbcommon0 libgbm1 libasound2`.

---

## Contributing

PRs welcome. The repo is small and the bar is concrete: every change should keep
`bazel test //...` green on whatever platform you're on, and `tools/update_checksums.py`
should still regenerate `private/versions.bzl` bit-identically.

Conventions:

- New rules need an analysis test in `tests/analysis_tests.bzl` so they fail fast at
  `bazel build` time without needing a browser.
- Bumping the pinned Playwright version: edit `package.json` to the new version,
  run `pnpm install --lockfile-only` to refresh `pnpm-lock.yaml`, then run
  `bash tools/update_checksums.sh <new-version>` to refresh `private/versions.bzl`.
  `//tests:version_drift_test` will fail until both files agree.
- `MODULE.bazel.lock` is intentionally not committed (matches sibling rules); don't
  add it.

### Help wanted: macOS validation

**This is the highest-leverage thing an outside contributor can do right now.**
v0.1 ships pinned `chromium` and `chromium_headless_shell` bundles for `darwin_amd64`
and `darwin_arm64` (sha256s in `private/versions.bzl`), but the rule has only been
exercised end-to-end on `linux_amd64`. Specifically unverified:

- That the macOS chromium bundle's headless binary lives where Playwright expects
  it under `<browsers_root>/chromium_headless_shell-1148/`. Linux ships
  `chrome-linux/headless_shell`; macOS may ship a different relative layout, and
  if so the launcher / bundle assembly needs a per-platform shim.
- That `playwright_bundle`'s file globbing picks up macOS `.app` bundle internals
  (lots of nested resources) without surprises.
- That `register_toolchains` resolves `darwin_amd64` and `darwin_arm64` correctly
  against the `@platforms//os:osx` constraints.

To validate on a Mac:

```bash
# 1. Host prereqs (one-time):
brew install bazelisk node corepack
corepack enable pnpm
xcode-select --install   # for Bazel's cc toolchain (rules_itest builds a small C sentinel)

# 2. Clone and run the test sweep:
git clone https://github.com/collider-bazel-extensions/rules_playwright
cd rules_playwright
pnpm install --frozen-lockfile
bazel test //... --test_tag_filters=-manual
```

Expected outcome: 7 tests pass, including `//tests:smoke_test`,
`//examples/basic:smoke_test`, and `//examples/itest:ui_test`.

If you hit failures:

- **Playwright says it can't find a browser executable.** Check what subpath it's
  looking for in the error (e.g. `chrome-mac/Chromium.app/...` vs.
  `chrome-mac/headless_shell`), unzip the bundle Bazel downloaded
  (`bazel info output_base` → `external/+playwright+playwright_chromium_headless_shell_darwin_*/`),
  and compare against what Playwright wants. Open an issue with the diff —
  this is the most likely failure mode.
- **`cc_binary` link errors from rules_itest's `exit0`.** Make sure Xcode CLT is
  installed (`xcode-select -p` should print a path).
- **Anything else.** File an issue with the full `bazel test` output and your
  `bazel info release` + macOS version; we'll triage.

A successful run on either darwin platform — even just a green CI log pasted in an
issue — is enough to flip the macOS row in `DESIGN.md`'s status table from
**outstanding** to **green**.
