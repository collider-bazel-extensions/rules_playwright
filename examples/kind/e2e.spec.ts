import { expect, test } from "@playwright/test";

test("nginx default page is reachable through the port-forward", async ({ page }) => {
  const resp = await page.goto("/");
  expect(resp?.ok()).toBe(true);
  await expect(page).toHaveTitle(/Welcome to nginx/);
});
