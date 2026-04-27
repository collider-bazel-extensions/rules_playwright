import { expect, test } from "@playwright/test";

test("data: URL renders text", async ({ page }) => {
  await page.goto("data:text/html,<h1>hello</h1>");
  await expect(page.locator("h1")).toHaveText("hello");
});
