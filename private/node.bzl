"""Node from the rules_nodejs runtime toolchain, and the `@playwright/test`
version check, shared by playwright_test / playwright_server /
playwright_binary."""

NODE_TOOLCHAIN = "@rules_nodejs//nodejs:runtime_toolchain_type"

def node_runtime(ctx):
    """Returns (`--node` value for launcher.py, depset of node's files).

    The node binary is the target platform's, from whatever rules_nodejs
    runtime toolchain the build registers (rules_nodejs registers its
    default node for every module). A toolchain configured with an
    absolute `node_path` instead of a fetched node is passed through.
    """
    info = ctx.toolchains[NODE_TOOLCHAIN].nodeinfo
    if info.node:
        return info.node.short_path, depset([info.node])
    return info.node_path, depset()

def playwright_version_check(ctx, version):
    """Validation action: the `@playwright/test` in `data` must be the
    toolchain's pinned Playwright `version`, or `bazel build` fails. A
    different runner looks for browser revisions the pinned bundles don't
    have. Skipped in `system` mode (the host's own Playwright)."""
    if version == "system" or not ctx.files.data:
        return []
    out = ctx.actions.declare_file(ctx.label.name + ".playwright_version_check")
    args = ctx.actions.args()
    args.add("--want", version)
    args.add("--label", str(ctx.label))
    args.add("--out", out)
    args.add_all(ctx.files.data, expand_directories = False)
    ctx.actions.run(
        executable = ctx.executable._version_check,
        arguments = [args],
        inputs = ctx.files.data,
        outputs = [out],
        mnemonic = "PlaywrightVersionCheck",
        progress_message = "Checking @playwright/test version for %{label}",
    )
    return [out]

VERSION_CHECK_ATTR = attr.label(
    default = "//private:version_check",
    executable = True,
    cfg = "exec",
)
