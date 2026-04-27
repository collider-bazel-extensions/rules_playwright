"""Toolchain + bundle rules.

`playwright_bundle` wraps an extracted bundle directory into a
`PlaywrightBundleInfo`. `playwright_toolchain` exposes a list of bundles
plus the host `npx` as a `ToolchainInfo`.
"""

load("//private:providers.bzl", "PlaywrightBinaryInfo", "PlaywrightBundleInfo")

PLAYWRIGHT_TOOLCHAIN_TYPE = Label("//toolchain:playwright")

# ---- playwright_bundle ------------------------------------------------------

def _bundle_impl(ctx):
    if not ctx.files.files:
        fail("playwright_bundle '{}': no files (empty bundle?)".format(ctx.label))
    dir_name = "{}-{}".format(ctx.attr.bundle_name, ctx.attr.revision)
    # Pick any file inside the bundle dir as a "root marker" — used by the
    # browsers-root assembly action to derive each bundle's source path
    # without paying for a depset traversal.
    root = None
    for f in ctx.files.files:
        if "/" + dir_name + "/" in f.short_path or f.short_path.startswith(dir_name + "/"):
            root = f
            break
    if root == None:
        fail("playwright_bundle '{}': no file found under '{}/' — extraction layout drift?".format(
            ctx.label,
            dir_name,
        ))
    return [
        DefaultInfo(files = depset(ctx.files.files), runfiles = ctx.runfiles(files = ctx.files.files)),
        PlaywrightBundleInfo(
            name = ctx.attr.bundle_name,
            revision = ctx.attr.revision,
            dir_name = dir_name,
            files = depset(ctx.files.files),
            root = root,
        ),
    ]

playwright_bundle = rule(
    implementation = _bundle_impl,
    attrs = {
        "bundle_name": attr.string(mandatory = True),
        "revision": attr.string(mandatory = True),
        "files": attr.label_list(allow_files = True, mandatory = True),
    },
)

# ---- playwright_toolchain ---------------------------------------------------

def _toolchain_impl(ctx):
    bundles = [b[PlaywrightBundleInfo] for b in ctx.attr.bundles]

    binary_info = PlaywrightBinaryInfo(
        version = ctx.attr.version,
        executable = ctx.executable.npx,
        node = None,
        runfiles = depset(transitive = [b.files for b in bundles]),
    )
    return [
        platform_common.ToolchainInfo(
            playwright = binary_info,
            bundles = bundles,
        ),
        DefaultInfo(),
    ]

playwright_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "bundles": attr.label_list(providers = [PlaywrightBundleInfo]),
        "npx": attr.label(executable = True, cfg = "exec", allow_single_file = True),
    },
)
