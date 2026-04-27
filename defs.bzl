"""Public API for rules_playwright.

Mirrors the surface of rules_pg / rules_temporal / rules_kind: re-exports of
private impl symbols + providers. Anything not re-exported here is private.
"""

load("//private:playwright_binary.bzl", _playwright_binary = "playwright_binary")
load("//private:playwright_health_check.bzl", _playwright_health_check = "playwright_health_check")
load("//private:playwright_server.bzl", _playwright_server = "playwright_server")
load("//private:playwright_test.bzl", _playwright_test = "playwright_test")
load(
    "//private:providers.bzl",
    _PlaywrightBinaryInfo = "PlaywrightBinaryInfo",
    _PlaywrightBundleInfo = "PlaywrightBundleInfo",
)

playwright_binary = _playwright_binary
playwright_test = _playwright_test
playwright_server = _playwright_server
playwright_health_check = _playwright_health_check

PlaywrightBinaryInfo = _PlaywrightBinaryInfo
PlaywrightBundleInfo = _PlaywrightBundleInfo
