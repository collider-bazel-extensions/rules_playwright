#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no playwright.version() in the root resolves, and the generated
#      @playwright hub's toolchain is rules_playwright's version
#   2. the same tag twice in the root resolves
#   3. an unsupported version fails, naming playwright.version
#   4. one repo name declared two ways in the root fails clearly
#   5. tests/ and examples/ are not shipped; @rules_playwright//private/... loads
#   6. with no node.toolchain() of its own, a consumer's playwright_binary
#      runs rules_nodejs's default node, from runfiles (not PATH)
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_playwright"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests examples; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
version="$(grep -A3 '^playwright.version(' "$src/MODULE.bazel" | sed -n 's/^ *version = "\(.*\)",$/\1/p')"
hub="@@rules_playwright++playwright+playwright"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    touch "$c/BUILD.bazel"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_playwright")
local_path_override(module_name = "rules_playwright", path = "$src")
$2
MOD
    echo "$c"
}

expect_fail() { # <consumer dir> <expected message>
    if (cd "$1" && bazel mod deps) > "$1.out" 2>&1; then
        echo "FAIL: $(basename "$1") resolved" >&2; exit 1
    fi
    grep -qF "$2" "$1.out" || { cat "$1.out" >&2; echo "FAIL: $(basename "$1"): wrong error" >&2; exit 1; }
}

# 1. No playwright.version(): resolves; the hub's toolchain has the version.
c="$(consumer untagged "")"
(cd "$c" && bazel mod deps >/dev/null)
(cd "$c" && bazel query "$hub//:linux_amd64_impl" --output=build) > "$work/untagged.out"
grep -q "version = \"$version\"" "$work/untagged.out" || { cat "$work/untagged.out" >&2; echo "FAIL: hub toolchain is not $version" >&2; exit 1; }
echo "PASS: untagged root resolves, playwright $version"

# 2. The same tag twice in the root.
c="$(consumer twice "playwright = use_extension(\"@rules_playwright//:extensions.bzl\", \"playwright\")
playwright.version(version = \"$version\")
playwright.version(version = \"$version\")")"
(cd "$c" && bazel mod deps >/dev/null)
echo "PASS: repeated identical playwright.version resolves"

# 3. Unsupported version.
c="$(consumer unsupported 'playwright = use_extension("@rules_playwright//:extensions.bzl", "playwright")
playwright.version(version = "0.0.1")')"
expect_fail "$c" 'playwright.version(version = "0.0.1") is not supported'
echo "PASS: unsupported version fails clearly"

# 4. One name, declared as version and system.
c="$(consumer conflict "playwright = use_extension(\"@rules_playwright//:extensions.bzl\", \"playwright\")
playwright.version(version = \"$version\")
playwright.system()")"
expect_fail "$c" 'declares repo "playwright" twice, differently'
echo "PASS: conflicting declarations fail clearly"

# 5. The shipped packages load (the root package loads the dev-only @npm).
(cd "$work/untagged" && bazel query "@rules_playwright//private/... + @rules_playwright//toolchain/..." >/dev/null)
echo "PASS: @rules_playwright//private/... and //toolchain/... load"

# 6. node comes from rules_nodejs's default runtime toolchain. With no
#    @playwright/test in `data`, the launcher gets past node and stops at
#    cli.js, so its message proves which node it resolved.
cat > "$work/untagged/BUILD.bazel" <<'BUILD'
load("@rules_playwright//:defs.bzl", "playwright_binary")

playwright_binary(name = "pw")
BUILD
(cd "$work/untagged" && bazel build //:pw >/dev/null 2>&1)
node_arg="$(sed -n 's/.*--node "\([^"]*\)".*/\1/p' "$work/untagged/bazel-bin/pw.sh")"
[[ "$node_arg" == ../rules_nodejs++node+nodejs_linux_amd64/* ]] || { echo "FAIL: --node is '$node_arg', not rules_nodejs's default node" >&2; exit 1; }
[[ -x "$work/untagged/bazel-bin/pw.sh.runfiles/${node_arg#../}" ]] || { echo "FAIL: $node_arg is not in runfiles" >&2; exit 1; }
nonode="$work/path-without-node"
mkdir -p "$nonode"
for f in /usr/bin/*; do
    case "$(basename "$f")" in node|nodejs|npx|npm|corepack) continue ;; esac
    ln -s "$f" "$nonode/"
done
if (cd "$work/untagged" && env PATH="$nonode" bazel-bin/pw.sh --version) > "$work/pw.out" 2>&1; then
    echo "FAIL: pw ran without @playwright/test" >&2; exit 1
fi
grep -q "@playwright/test/cli.js not found" "$work/pw.out" || { cat "$work/pw.out" >&2; echo "FAIL: launcher did not resolve node" >&2; exit 1; }
echo "PASS: playwright_binary runs rules_nodejs's node ($node_arg), not the host's"
