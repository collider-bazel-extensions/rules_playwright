"""playwright_server — long-running `npx playwright run-server`.

Drops into `itest_service.exe` (see [`rules_itest` integration](#rules_itest-integration)
in the README). Pass `@playwright/test` and any other npm runtime via `data`,
e.g. `data = ["//:node_modules/@playwright/test"]` under aspect_rules_js.

The server's listen port is taken (in priority order):
1. `$PORT` env var, if set — composes with `itest_service.autoassign_port`,
   which exports the assigned port via `env = {"PORT": port(":svc")}`;
2. otherwise the build-time `port` attr (default 0, meaning Playwright
   picks any free port).

Browser bundles come from the toolchain and are assembled into the same
`browsers/` runfiles tree as `playwright_test`.
"""

load("//private:bundle_assembly.bzl", "bundle_runfiles_symlinks", "select_bundles")

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:playwright"]
    bundles = select_bundles(getattr(tc, "bundles", []), ctx.attr.browsers)
    bundle_symlinks, bundle_files = bundle_runfiles_symlinks(bundles)

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{PORT}": str(ctx.attr.port),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [ctx.executable._launcher] + ctx.files.data,
        transitive_files = bundle_files,
        symlinks = bundle_symlinks,
    )
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

playwright_server = rule(
    implementation = _impl,
    attrs = {
        "port": attr.int(
            default = 0,
            doc = "Build-time default port. 0 = Playwright picks. Overridden " +
                  "at runtime by `$PORT` if set (e.g. via `itest_service.env`).",
        ),
        "data": attr.label_list(allow_files = True),
        "browsers": attr.string_list(default = ["chromium"]),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_tmpl": attr.label(
            default = "//private:server.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:playwright"],
    executable = True,
)
