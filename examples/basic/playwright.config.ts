import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  reporter: "list",
  use: {
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
