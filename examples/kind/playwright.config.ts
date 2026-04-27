import { defineConfig, devices } from "@playwright/test";

const port = process.env.PORT_app;
if (!port) throw new Error("PORT_app not set — run via service_test");

export default defineConfig({
  testDir: ".",
  reporter: "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
