"""playwright_binary — `bazel run` entrypoint for ad-hoc `playwright …`, on
the rules_nodejs toolchain's node.

Pass `@playwright/test` (and any other npm runtime) via `data`, e.g.
`data = ["//:node_modules/@playwright/test"]` under aspect_rules_js, or a
filegroup over a manually-installed node_modules. Browser bundles are not
attached: most ad-hoc invocations (`--version`, `--help`, codegen against
arbitrary URLs) don't need them. Targets that *do* need a hermetic browser
should use `playwright_test` or `playwright_server` instead.
"""

load("//private:node.bzl", "NODE_TOOLCHAIN", "VERSION_CHECK_ATTR", "node_runtime", "playwright_version_check")

def _impl(ctx):
    node_arg, node_files = node_runtime(ctx)
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{NODE}": node_arg,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.executable._launcher] + ctx.files.data, transitive_files = node_files)
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    version = ctx.toolchains["//toolchain:playwright"].playwright.version
    return [
        DefaultInfo(executable = out, runfiles = runfiles),
        OutputGroupInfo(_validation = depset(playwright_version_check(ctx, version))),
    ]

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
        "_version_check": VERSION_CHECK_ATTR,
    },
    toolchains = ["//toolchain:playwright", NODE_TOOLCHAIN],
    executable = True,
)
