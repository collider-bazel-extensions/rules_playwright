"""Providers exported by rules_playwright."""

PlaywrightBinaryInfo = provider(
    doc = "The resolved Playwright CLI for a single (version, platform).",
    fields = {
        "version": "Playwright version string, e.g. '1.49.0'.",
        "executable": "File: the `playwright` (or `npx playwright`) launcher.",
        "node": "File: the bundled node binary, if any (None in `system` mode).",
        "runfiles": "depset[File]: everything `executable` needs at runtime.",
    },
)

PlaywrightBundleInfo = provider(
    doc = "A single Playwright browser-cache bundle (e.g. chromium-1148, " +
          "chromium_headless_shell-1148, ffmpeg-1011). One bundle == one " +
          "directory in PLAYWRIGHT_BROWSERS_PATH.",
    fields = {
        "name": "Bundle name as Playwright knows it (e.g. 'chromium').",
        "revision": "Revision string (e.g. '1148').",
        "dir_name": "'<name>-<revision>' — the directory name Playwright " +
                    "expects under PLAYWRIGHT_BROWSERS_PATH.",
        "files": "depset[File]: every file that lives inside the bundle dir.",
        "root": "File: a marker file at the bundle dir's root, used to " +
                "compute the bundle's runfiles short_path. Any file inside " +
                "the extracted tree works.",
    },
)
