import { test, expect } from "@playwright/test";
import { EVENT_CODE } from "./helpers";

test.describe("legacy Claper routes stay intact", () => {
  test("audience room, classic agenda, and bingo respond", async ({ page }) => {
    for (const route of [`/e/${EVENT_CODE}`, `/e/${EVENT_CODE}/agenda`, `/e/${EVENT_CODE}/bingo`]) {
      const response = await page.goto(route);
      expect(response?.status()).toBe(200);
    }
  });

  test("classic agenda shows event-local times", async ({ page }) => {
    await page.goto(`/e/${EVENT_CODE}/agenda`);
    await expect(page.getByText("E2E Opening Keynote")).toBeVisible();
    await expect(page.getByText("Jul 25, 08:30")).toBeVisible();
  });
});
