"""Analysis-time tests for the rules.

Verify rules instantiate cleanly and expose the expected DefaultInfo without
needing to execute a browser. Mirrors the pattern used by rules_pg / rules_temporal.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_playwright//:defs.bzl", "playwright_server", "playwright_test")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def playwright_test_test_suite(name):
    playwright_test(
        name = name + "_subject",
        srcs = ["smoke.spec.ts"],
        config = "playwright.config.ts",
        tags = ["manual"],
    )
    _has_executable_test(
        name = name + "_executable",
        target_under_test = ":" + name + "_subject",
    )
    native.test_suite(name = name, tests = [":" + name + "_executable"])

def playwright_server_test_suite(name):
    playwright_server(
        name = name + "_subject",
        port = 0,
        tags = ["manual"],
    )
    _has_executable_test(
        name = name + "_executable",
        target_under_test = ":" + name + "_subject",
    )
    native.test_suite(name = name, tests = [":" + name + "_executable"])
