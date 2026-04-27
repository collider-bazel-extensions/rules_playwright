"""playwright_binary — `bazel run` entrypoint for ad-hoc `npx playwright …`.

Pass `@playwright/test` (and any other npm runtime) via `data`, e.g.
`data = ["//:node_modules/@playwright/test"]` under aspect_rules_js, or a
filegroup over a manually-installed node_modules. Browser bundles are not
attached: most ad-hoc invocations (`--version`, `--help`, codegen against
arbitrary URLs) don't need them. Targets that *do* need a hermetic browser
should use `playwright_test` or `playwright_server` instead.
"""

def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.executable._launcher] + ctx.files.data)
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

playwright_binary = rule(
    implementation = _impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_tmpl": attr.label(
            default = "//private:binary.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:playwright"],
    executable = True,
)
