import { expect, test } from "@playwright/test";

test("fake app serves the title", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#title")).toHaveText("fake app");
});
