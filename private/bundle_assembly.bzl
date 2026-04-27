"""Helpers shared by playwright_test / _server / _binary for assembling
a Playwright-cache-shaped `browsers/` directory from toolchain bundles."""

load(":providers.bzl", "PlaywrightBundleInfo")  # buildifier: keep
load(":versions.bzl", "BROWSER_TYPE_BUNDLES")

def bundle_runfiles_symlinks(bundles):
    """Return (symlinks_dict, files_depset) laying out `bundles` under
    `browsers/<bundle.dir_name>/`. Pass `symlinks_dict` to `ctx.runfiles(symlinks=...)`
    and `files_depset` to `transitive_files=` so Bazel materialises the tree."""
    symlinks = {}
    file_depsets = []
    for b in bundles:
        marker = "/" + b.dir_name + "/"
        for f in b.files.to_list():
            sp = f.short_path
            idx = sp.find(marker)
            if idx < 0:
                if sp.startswith(b.dir_name + "/"):
                    rel = sp[len(b.dir_name) + 1:]
                else:
                    fail("playwright bundle file '{}' not under '{}/'".format(sp, b.dir_name))
            else:
                rel = sp[idx + len(marker):]
            symlinks["browsers/{}/{}".format(b.dir_name, rel)] = f
        file_depsets.append(b.files)
    return symlinks, depset(transitive = file_depsets)

def select_bundles(toolchain_bundles, browsers):
    """Filter the toolchain's bundle list down to just those required by the
    requested user-facing browser types. Fails on unknown browser types or
    missing bundles."""
    needed = []
    for browser in browsers:
        if browser not in BROWSER_TYPE_BUNDLES:
            fail("unknown browser type '{}'. Supported: {}".format(
                browser,
                sorted(BROWSER_TYPE_BUNDLES.keys()),
            ))
        for n in BROWSER_TYPE_BUNDLES[browser]:
            if n not in needed:
                needed.append(n)
    selected = [b for b in toolchain_bundles if b.name in needed]
    have = [b.name for b in selected]
    missing = [n for n in needed if n not in have]
    if missing:
        fail("toolchain is missing required bundle(s): {}".format(missing))
    return selected
