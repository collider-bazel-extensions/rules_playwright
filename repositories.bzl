"""WORKSPACE-mode mirror of the bzlmod extension.

Lets non-bzlmod consumers register Playwright versions via:

    load("@rules_playwright//:repositories.bzl",
         "rules_playwright_dependencies", "register_playwright_toolchains")
    rules_playwright_dependencies()
    register_playwright_toolchains(versions = ["1.49.0"])
"""

load(
    "//private:repositories.bzl",
    _playwright_system_repository = "playwright_system_repository",
    _playwright_version_repository = "playwright_version_repository",
)

playwright_version_repository = _playwright_version_repository
playwright_system_repository = _playwright_system_repository

def rules_playwright_dependencies():
    """No-op placeholder; transitive deps come from MODULE.bazel / WORKSPACE."""
    pass

def register_playwright_toolchains(name = "playwright", versions = []):
    """Materializes one repo per (version, platform) and registers toolchains."""
    for version in versions:
        repo = "{}_{}".format(name, version.replace(".", "_"))
        playwright_version_repository(name = repo, version = version)
        native.register_toolchains("@{}//:all".format(repo))
