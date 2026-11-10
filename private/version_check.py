#!/usr/bin/env python3
"""Validation action for playwright_test / playwright_server /
playwright_binary: the `@playwright/test` package in `data` must be the
toolchain's pinned Playwright version.

Inputs are the target's `data` files and directories (rules_js packages
are directory artifacts). Writes `--out` on success; exits 1 with a
message naming both versions otherwise. Passes when no `@playwright/test`
is in `data` (launcher.py reports that at run time, as before).
"""

from __future__ import annotations

import argparse
import json
import os
import sys

_SUFFIX = os.path.join("@playwright", "test", "package.json")


def _find_package_jsons(paths: list[str]) -> list[str]:
    found = []
    for p in paths:
        if os.path.isfile(p):
            if p.endswith(_SUFFIX):
                found.append(p)
            continue
        for root, _dirs, files in os.walk(p, followlinks=True):
            if "package.json" in files and root.endswith(os.path.join("@playwright", "test")):
                found.append(os.path.join(root, "package.json"))
    return found


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--want", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("paths", nargs="*")
    args = ap.parse_args(argv[1:])

    versions = {}
    for pj in _find_package_jsons(args.paths):
        with open(pj) as f:
            versions[json.load(f).get("version", "?")] = pj
    bad = sorted(v for v in versions if v != args.want)
    if bad:
        print("rules_playwright: {} has @playwright/test {} in `data`, but the "
              "Playwright toolchain is pinned to {} (playwright.version). Pin "
              "@playwright/test to {} in your lockfile, or set "
              "playwright.version(version = ...) to match.".format(
                  args.label, ", ".join(bad), args.want, args.want),
              file=sys.stderr)
        return 1
    with open(args.out, "w") as f:
        f.write("@playwright/test {}\n".format(args.want if versions else "(not in data)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
