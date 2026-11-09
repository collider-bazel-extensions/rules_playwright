"""Bzlmod extension. Same shape as rules_pg / rules_temporal / rules_kind:
two tag classes — `version` (download) and `system` (host-installed).
"""

load(
    "//private:repositories.bzl",
    "playwright_system_repository",
    "playwright_version_repository",
)
load("//private:versions.bzl", "PLAYWRIGHT_VERSIONS")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "playwright"),
    "version": attr.string(mandatory = True),
})

_system_tag = tag_class(attrs = {
    "name": attr.string(default = "playwright"),
    # Optional path hint; if unset, the repo rule auto-detects via `command -v npx`.
    "npx": attr.string(default = ""),
})

def _spec(kind, tag):
    if kind == "version":
        return ("version", tag.version)
    return ("system", tag.npx)

def _module_repos(mod):
    """{repo name: (kind, value)} for one module's tags."""
    repos = {}
    for kind, tags in [("version", mod.tags.version), ("system", mod.tags.system)]:
        for tag in tags:
            spec = _spec(kind, tag)
            if kind == "version" and tag.version not in PLAYWRIGHT_VERSIONS:
                fail("rules_playwright: playwright.version(version = \"{}\") is not supported. Supported: {}".format(
                    tag.version,
                    ", ".join(sorted(PLAYWRIGHT_VERSIONS.keys())),
                ))
            if tag.name in repos and repos[tag.name] != spec:
                fail("rules_playwright: {} declares repo \"{}\" twice, differently (playwright.{}); declare it once.".format(
                    "the root module" if mod.is_root else mod.name,
                    tag.name,
                    " and playwright.".join(sorted([repos[tag.name][0], kind])),
                ))
            repos[tag.name] = spec
    return repos

def _impl(mctx):
    # The extension runs once for the whole build and sees every module's
    # tags; each repo name must be created once. rules_playwright's own
    # MODULE.bazel declares `@playwright` (and registers its toolchain) for
    # every consumer, so its tags count too: per repo name, the root
    # module's tag wins, else rules_playwright's. Other modules' tags are
    # ignored. Through v0.2.0 only the root's tags counted, so a root
    # without `playwright.version()` failed to resolve ("does not generate
    # repository playwright").
    root = {}
    own = {}
    for mod in mctx.modules:
        if mod.is_root:
            root = _module_repos(mod)
        elif mod.name == "rules_playwright":
            own = _module_repos(mod)
    repos = dict(own)
    repos.update(root)
    for name, (kind, value) in repos.items():
        if kind == "version":
            playwright_version_repository(name = name, version = value)
        else:
            playwright_system_repository(name = name, npx_hint = value)

playwright = module_extension(
    implementation = _impl,
    tag_classes = {
        "version": _version_tag,
        "system": _system_tag,
    },
)
