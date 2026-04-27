"""playwright_server — long-running `npx playwright run-server`.

Drops into `itest_service.exe`. Companion: `playwright_health_check`.
Assembles the same `browsers/` runfiles tree as `playwright_test` so the
running server has hermetic access to its browser bundles.
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
        files = [ctx.executable._launcher],
        transitive_files = bundle_files,
        symlinks = bundle_symlinks,
    )
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

playwright_server = rule(
    implementation = _impl,
    attrs = {
        "port": attr.int(default = 0, doc = "0 = let itest pick."),
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
