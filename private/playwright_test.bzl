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
load("//private:versions.bzl", "BROWSER_TYPE_BUNDLES")

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:playwright"]
    bundles = select_bundles(getattr(tc, "bundles", []), ctx.attr.browsers)
    bundle_symlinks, bundle_files = bundle_runfiles_symlinks(bundles)

    # browsers is a single-element list at the rule layer (the macro fans
    # out multi-browser callers into N rule instances, one browser each).
    # Use the singular browser literal as Playwright's --project name; the
    # consumer's playwright.config.ts must declare matching projects.
    browser = ctx.attr.browsers[0]

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._launcher_tmpl,
        output = runner,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{CONFIG}": ctx.file.config.short_path if ctx.file.config else "",
            "{BROWSER}": browser,
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
    """Hermetic Playwright test target.

    When `browsers` contains more than one entry, the macro fans out into one
    `_playwright_test` rule per browser (named `<name>_<browser>`) plus a
    `test_suite` named `<name>` that aggregates them. Each per-browser target
    carries the browser literal as a tag so `--test_tag_filters=-webkit` etc.
    work for CI matrix selection. The consumer's `playwright.config.ts` must
    declare a `projects:` entry per browser whose `name` matches the literal.

    See module docstring for the broader runtime contract.
    """
    if not browsers:
        fail("playwright_test: `browsers` must be non-empty.")
    for b in browsers:
        if b not in BROWSER_TYPE_BUNDLES:
            fail("playwright_test: unknown browser '{}'. Supported: {}".format(
                b, sorted(BROWSER_TYPE_BUNDLES.keys())))

    base_tags = tags + ["playwright", "requires-network", "no-sandbox"]

    if len(browsers) == 1:
        _playwright_test(
            name = name,
            srcs = srcs,
            config = config,
            data = data,
            browsers = browsers,
            tags = base_tags + browsers,
            **kwargs
        )
        return

    inner_names = []
    for b in browsers:
        inner = "{}_{}".format(name, b)
        inner_names.append(inner)
        _playwright_test(
            name = inner,
            srcs = srcs,
            config = config,
            data = data,
            browsers = [b],
            tags = base_tags + [b],
            **kwargs
        )
    native.test_suite(
        name = name,
        tests = [":" + n for n in inner_names],
        tags = tags,
    )
