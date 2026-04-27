"""Fail if pnpm-lock.yaml's @playwright/test version isn't pinned in
private/versions.bzl. Catches the easy footgun where someone bumps
@playwright/test in package.json but forgets to refresh PLAYWRIGHT_VERSIONS
(or vice versa). The two need to track because the runner library and the
browser bundle revisions are coupled by Playwright."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def _runfiles_path(rel: str) -> Path:
    rfd = os.environ.get("RUNFILES_DIR") or os.environ.get("TEST_SRCDIR")
    if rfd:
        for prefix in ("_main", ""):
            cand = Path(rfd) / prefix / rel if prefix else Path(rfd) / rel
            if cand.is_file():
                return cand
    return Path(rel)


def lock_version() -> str:
    text = _runfiles_path("pnpm-lock.yaml").read_text()
    # Match the importers.<root>.devDependencies['@playwright/test'].specifier
    # field: a `specifier:` line directly under a stanza naming @playwright/test.
    blocks = re.split(r"^      '@playwright/test':\n", text, flags=re.M)
    if len(blocks) < 2:
        raise AssertionError(
            "Could not locate '@playwright/test' devDependency in pnpm-lock.yaml. "
            "This test assumes the package is declared at the workspace root.")
    m = re.search(r"^        specifier:\s*([^\s]+)", blocks[1], re.M)
    if not m:
        raise AssertionError("'@playwright/test' has no specifier line in pnpm-lock.yaml.")
    return m.group(1)


def manifest_versions() -> set[str]:
    text = _runfiles_path("private/versions.bzl").read_text()
    return set(re.findall(r'^\s*"(\d+\.\d+\.\d+)":\s*\{', text, flags=re.M))


def main() -> int:
    lock = lock_version()
    versions = manifest_versions()
    if not versions:
        print("FAIL: PLAYWRIGHT_VERSIONS in private/versions.bzl appears empty.", file=sys.stderr)
        return 1
    if lock not in versions:
        print(
            f"FAIL: pnpm-lock.yaml pins @playwright/test=={lock}, but "
            f"private/versions.bzl only knows about {sorted(versions)}.\n"
            f"Bump one to match the other (typically rerun "
            f"`tools/update_checksums.sh {lock}` and refresh package.json).",
            file=sys.stderr,
        )
        return 1
    print(f"OK: @playwright/test {lock} matches PLAYWRIGHT_VERSIONS.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
