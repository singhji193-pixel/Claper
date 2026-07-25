import { test, expect } from "@playwright/test";
import { EVENT_CODE, OWNER_STATE, waitForLiveView } from "./helpers";

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

test.describe("classic attendee poll layout", () => {
  test.use({ storageState: OWNER_STATE });

  test("launched poll keeps Vote visible and clickable", async ({ page }) => {
    await page.goto(`/e/${EVENT_CODE}`);
    await waitForLiveView(page);

    await expect(page.getByText("E2E favourite track?")).toBeVisible();
    await page.locator("#poll-opt-0").click();

    const wrapper = page.locator("#poll-wrapper-parent");
    const vote = page.locator('#extended-poll button[phx-click="vote"]');

    await wrapper.evaluate((element) => {
      element.scrollTop = element.scrollHeight;
    });

    await expect(vote).toBeVisible();
    await expect(vote).toBeEnabled();

    const geometry = await vote.evaluate((button) => {
      const rect = button.getBoundingClientRect();
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      const hit = document.elementFromPoint(x, y);

      return {
        top: rect.top,
        bottom: rect.bottom,
        viewportHeight: window.visualViewport?.height ?? window.innerHeight,
        topmost: hit === button || button.contains(hit),
      };
    });

    expect(geometry.top).toBeGreaterThanOrEqual(0);
    expect(geometry.bottom).toBeLessThanOrEqual(geometry.viewportHeight);
    expect(geometry.topmost).toBe(true);
    await vote.click({ trial: true });
  });
});
