"""playwright_test — runs `npx playwright test` against hermetic browser bundles.

Contract:
- Caller provides a `playwright.config.ts` (or accepts the default discovery).
- Runfiles must include `node_modules/@playwright/test` — supplied via
  `data` (e.g. `aspect_rules_js`'s `npm_link_package`, or a manually-installed
  `node_modules` filegroup). Host `node` + `npx` must be on PATH.
- Browser bundles come from the toolchain. We assemble a `browsers/` tree in
  runfiles whose layout matches Playwright's cache (`<name>-<rev>/...`) and
  point `PLAYWRIGHT_BROWSERS_PATH` there. `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`
  is set so Playwright never reaches out to the network.

Tags: `["playwright", "requires-network", "no-sandbox"]` always added.
"""

load("//private:bundle_assembly.bzl", "bundle_runfiles_symlinks", "select_bundles")

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:playwright"]
    bundles = select_bundles(getattr(tc, "bundles", []), ctx.attr.browsers)
    bundle_symlinks, bundle_files = bundle_runfiles_symlinks(bundles)

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._launcher_tmpl,
        output = runner,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{CONFIG}": ctx.file.config.short_path if ctx.file.config else "",
            "{SPECS}": " ".join([f.short_path for f in ctx.files.srcs]),
        },
        is_executable = True,
    )

    direct_files = list(ctx.files.srcs) + list(ctx.files.data) + [ctx.executable._launcher]
    if ctx.file.config:
        direct_files.append(ctx.file.config)
    runfiles = ctx.runfiles(
        files = direct_files,
        transitive_files = bundle_files,
        symlinks = bundle_symlinks,
    )
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

_playwright_test = rule(
    implementation = _impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".ts", ".js"]),
        "config": attr.label(allow_single_file = True),
        "data": attr.label_list(allow_files = True),
        "browsers": attr.string_list(default = ["chromium"]),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_launcher_tmpl": attr.label(
            default = "//private:launcher.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:playwright"],
    test = True,
)

def playwright_test(name, srcs, config = None, data = [], browsers = ["chromium"], tags = [], **kwargs):
    """Hermetic Playwright test target. See module docstring for runtime contract."""
    if browsers != ["chromium"]:
        fail("playwright_test: v0.1.0 supports only `browsers = [\"chromium\"]`")
    _playwright_test(
        name = name,
        srcs = srcs,
        config = config,
        data = data,
        browsers = browsers,
        tags = tags + ["playwright", "requires-network", "no-sandbox"],
        **kwargs
    )
