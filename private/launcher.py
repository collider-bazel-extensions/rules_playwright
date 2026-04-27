#!/usr/bin/env python3
"""Runtime launcher for playwright_test / playwright_server / playwright_binary.

Same role as launcher.py in rules_pg / rules_temporal / rules_kind. Owns:
- env setup (PLAYWRIGHT_BROWSERS_PATH, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD,
  HOME, TMPDIR)
- direct invocation of `@playwright/test`'s `cli.js` via `node` — we don't
  use `npx`, both because rules_js's virtual-store layout doesn't expose a
  `node_modules/.bin/playwright` and because direct invocation is simpler:
  cli.js's `require('playwright/...')` resolves via its own realpath, where
  peer deps live as siblings in the virtual store
- a per-test working dir of *real* spec/config files (Playwright's discovery
  uses readdir(withFileTypes=True) and skips symlink entries; Bazel runfiles
  are all symlinks, so we hardlink real files into TEST_TMPDIR/pw_specs/ and
  cd there before running Playwright)
- exec of the underlying tool
- SIGTERM/SIGINT forwarding so itest can stop us cleanly
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys


def _resolve_runfiles(rel: str) -> str:
    rfd = os.environ.get("RUNFILES_DIR") or os.environ.get("TEST_SRCDIR")
    if not rfd:
        return rel
    candidate = os.path.join(rfd, "_main", rel)
    if os.path.exists(candidate):
        return candidate
    candidate = os.path.join(rfd, rel)
    if os.path.exists(candidate):
        return candidate
    return rel


def _candidate_dirs(rfd: str, hint: str | None) -> list[str]:
    """Ordered list of directories to probe for `node_modules/`. Covers:
    workspace-root layout (rules_js Option A → `<rfd>/_main`), bare runfiles
    root (legacy), and the test target's own package dir (Option B,
    `<rfd>/_main/<pkg>/node_modules` — derived from a spec's short_path)."""
    dirs = [os.path.join(rfd, "_main"), rfd]
    if hint:
        pkg = os.path.dirname(hint)
        if pkg:
            dirs.insert(0, os.path.join(rfd, "_main", pkg))
            dirs.insert(1, os.path.join(rfd, pkg))
    return dirs


def _find_cli_js(rfd: str, hint: str | None) -> str | None:
    """Locate @playwright/test/cli.js in runfiles. Returns its realpath
    (the virtual-store location) so node's module resolution sees its peer
    deps as siblings. Probes conventional locations first; only falls back
    to a recursive search that follows symlinks if none hit."""
    rel = "node_modules/@playwright/test/cli.js"
    for d in _candidate_dirs(rfd, hint):
        cand = os.path.join(d, rel)
        if os.path.isfile(cand):
            return os.path.realpath(cand)
    for root, _dirs, files in os.walk(rfd, followlinks=True):
        if root.endswith("/node_modules/@playwright/test") and "cli.js" in files:
            return os.path.realpath(os.path.join(root, "cli.js"))
    return None


def _hardlink_into(tmpdir: str, src_runfiles_path: str) -> str:
    real = os.path.realpath(src_runfiles_path)
    dst = os.path.join(tmpdir, os.path.basename(real))
    if os.path.exists(dst):
        os.remove(dst)
    try:
        os.link(real, dst)
    except OSError:
        shutil.copy2(real, dst)
    return dst


def _node_modules_root(rfd: str, hint: str | None) -> str | None:
    """Locate the runfiles `node_modules` dir. Probes (in order):
    `<rfd>/_main/<pkg>/node_modules` (Option B, manual filegroup colocated
    with specs), `<rfd>/_main/node_modules` (Option A, rules_js workspace
    root), bare runfiles root. Only falls back to walking if none hit."""
    for d in _candidate_dirs(rfd, hint):
        cand = os.path.join(d, "node_modules")
        if os.path.isdir(cand):
            return cand
    for root, dirs, _ in os.walk(rfd, followlinks=False):
        if "node_modules" in dirs:
            return os.path.join(root, "node_modules")
    return None


def _stage_specs(specs: list[str], config: str | None, node_modules_src: str | None) -> tuple[str, list[str], str | None]:
    """Hardlink each spec (and the config) into a fresh tmpdir of real files
    so Playwright's discovery (which skips symlinks via readdir withFileTypes)
    finds them. Symlink `node_modules` next to them so the user's
    `import "@playwright/test"` in the config resolves via node's
    walk-up-from-cwd. Plant a stub `package.json` so Playwright anchors its
    `outputDir` (default `<pkg-dir>/test-results`) inside the writable
    tmpdir instead of walking up into the sandbox-readonly home dir.
    Returns (cwd, hardlinked_specs, hardlinked_config)."""
    tmpdir = os.path.join(os.environ.get("TEST_TMPDIR") or "/tmp", "pw_specs")
    os.makedirs(tmpdir, exist_ok=True)
    if node_modules_src:
        link = os.path.join(tmpdir, "node_modules")
        if os.path.islink(link):
            os.remove(link)
        elif os.path.exists(link):
            shutil.rmtree(link)
        os.symlink(node_modules_src, link)
    pkg_json = os.path.join(tmpdir, "package.json")
    if not os.path.exists(pkg_json):
        with open(pkg_json, "w") as f:
            f.write('{"name":"_rules_playwright_test_staging","private":true}\n')
    new_specs = [_hardlink_into(tmpdir, _resolve_runfiles(s)) for s in specs]
    new_config = _hardlink_into(tmpdir, _resolve_runfiles(config)) if config else None
    return tmpdir, new_specs, new_config


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["test", "server", "binary"], required=True)
    ap.add_argument("--config", default="", help="playwright.config.ts (optional).")
    ap.add_argument("--specs", nargs="*", default=[], help="Spec files (test mode).")
    ap.add_argument("--port", type=int, default=0, help="Server mode port.")
    ap.add_argument("forward", nargs=argparse.REMAINDER,
                    help="Trailing args after `--` go to the underlying tool.")
    args = ap.parse_args(argv[1:])

    env = os.environ.copy()
    rfd = env.get("RUNFILES_DIR") or env.get("TEST_SRCDIR")

    # Point Playwright at the runfiles `browsers/` tree assembled by the rule.
    if rfd:
        for cand in (os.path.join(rfd, "_main", "browsers"), os.path.join(rfd, "browsers")):
            if os.path.isdir(cand):
                env["PLAYWRIGHT_BROWSERS_PATH"] = cand
                break
    env["PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD"] = "1"
    env["HOME"] = env.get("TEST_TMPDIR", env.get("TMPDIR", "/tmp"))

    node = shutil.which("node")
    if not node:
        print("rules_playwright: `node` not found on PATH", file=sys.stderr)
        return 127

    hint = args.specs[0] if args.specs else (args.config or None)
    cli_js = _find_cli_js(rfd, hint) if rfd else None
    if not cli_js:
        print("rules_playwright: @playwright/test/cli.js not found in runfiles. "
              "Add @playwright/test via the test target's `data` attribute "
              "(e.g. `//:node_modules/@playwright/test` under aspect_rules_js, "
              "or a filegroup over a manually-installed node_modules).",
              file=sys.stderr)
        return 127

    if args.mode == "test":
        nm_src = _node_modules_root(rfd, hint) if rfd else None
        cwd, staged_specs, staged_config = _stage_specs(args.specs, args.config or None, nm_src)
        os.chdir(cwd)
        cmd = [node, cli_js, "test"]
        if staged_config:
            cmd += ["--config", staged_config]
        cmd += staged_specs
    elif args.mode == "server":
        # $PORT (set by `itest_service.env = {"PORT": port(...)}`) wins over the
        # build-time `port` attr so the rule composes with rules_itest's
        # autoassign_port. Without an env override, fall through to the
        # build-time default for `bazel run :server` ergonomics.
        port = env.get("PORT")
        try:
            port_i = int(port) if port else args.port
        except ValueError:
            port_i = args.port
        cmd = [node, cli_js, "run-server", "--port", str(port_i)]
    else:  # binary
        # argparse.REMAINDER captures the literal `--` separator (used in
        # binary.sh.tmpl to keep argparse from consuming the user's own
        # flags); drop it before forwarding to Playwright.
        forward = args.forward or []
        if forward and forward[0] == "--":
            forward = forward[1:]
        cmd = [node, cli_js] + forward

    proc = subprocess.Popen(cmd, env=env)

    def forward(signum, _frame):
        proc.send_signal(signum)

    signal.signal(signal.SIGTERM, forward)
    signal.signal(signal.SIGINT, forward)
    return proc.wait()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
