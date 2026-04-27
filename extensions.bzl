"""Bzlmod extension. Same shape as rules_pg / rules_temporal / rules_kind:
two tag classes — `version` (download) and `system` (host-installed).
"""

load(
    "//private:repositories.bzl",
    "playwright_system_repository",
    "playwright_version_repository",
)

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "playwright"),
    "version": attr.string(mandatory = True),
})

_system_tag = tag_class(attrs = {
    "name": attr.string(default = "playwright"),
    # Optional path hint; if unset, the repo rule auto-detects via `command -v npx`.
    "npx": attr.string(default = ""),
})

def _impl(mctx):
    for mod in mctx.modules:
        for tag in mod.tags.version:
            playwright_version_repository(
                name = tag.name,
                version = tag.version,
            )
        for tag in mod.tags.system:
            playwright_system_repository(
                name = tag.name,
                npx_hint = tag.npx,
            )

playwright = module_extension(
    implementation = _impl,
    tag_classes = {
        "version": _version_tag,
        "system": _system_tag,
    },
)
