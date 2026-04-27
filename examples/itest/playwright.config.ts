import { defineConfig, devices } from "@playwright/test";

// rules_itest exports the allocated port for service `app` as PORT_app.
const port = process.env.PORT_app;
if (!port) {
  throw new Error("PORT_app not set — is this running under service_test?");
}

export default defineConfig({
  testDir: ".",
  reporter: "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
