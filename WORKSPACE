workspace(name = "rules_playwright")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "",  # tools/update_checksums.sh
    urls = ["https://github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz"],
)

http_archive(
    name = "platforms",
    sha256 = "",  # tools/update_checksums.sh
    urls = ["https://github.com/bazelbuild/platforms/releases/download/0.0.9/platforms-0.0.9.tar.gz"],
)

load("//:repositories.bzl", "rules_playwright_dependencies")

rules_playwright_dependencies()

load("//:repositories.bzl", "register_playwright_toolchains")

register_playwright_toolchains(versions = ["1.49.0"])
