import { test, expect } from "@playwright/test";
import { APP_BASE, ATTENDEE_STATE, expectNoHorizontalOverflow, waitForLiveView } from "./helpers";

test.use({ storageState: ATTENDEE_STATE });

test.describe("agenda", () => {
  test("shows event-local wall times and a single event day", async ({ page }) => {
    await page.goto(`${APP_BASE}/agenda`);

    // Stored 15:30 UTC renders as the 08:30 PDT keynote slot.
    await expect(page.getByText("E2E Opening Keynote")).toBeVisible();
    await expect(page.locator("time", { hasText: "08:30" }).first()).toBeVisible();

    // The 00:15 UTC reception stays on the same local day (no second day chip).
    await expect(page.getByText("E2E Evening Reception")).toBeVisible();
    await expect(page.locator("time", { hasText: "17:15" }).first()).toBeVisible();
    await expect(page.locator(".ngs-day")).toHaveCount(1);

    await expectNoHorizontalOverflow(page);
  });

  test("filters by track chip", async ({ page }) => {
    await page.goto(`${APP_BASE}/agenda`);

    await page.click('.ngs-chip:has-text("Networking")');
    await expect(page.getByText("E2E Evening Reception")).toBeVisible();
    await expect(page.getByText("E2E Opening Keynote")).not.toBeVisible();

    await page.click('.ngs-chip:has-text("All tracks")');
    await expect(page.getByText("E2E Opening Keynote")).toBeVisible();
  });

  test("searches sessions by speaker", async ({ page }) => {
    await page.goto(`${APP_BASE}/agenda?q=Jordan`);
    await expect(page.getByText("E2E Opening Keynote")).toBeVisible();
    await expect(page.getByText("E2E Evening Reception")).not.toBeVisible();
  });

  test("saves and unsaves a session", async ({ page }) => {
    await page.goto(`${APP_BASE}/agenda`);
    await waitForLiveView(page);

    const saveButton = page.locator(".ngs-save-button").first();
    await saveButton.click();
    await expect(page.getByText("Session saved.")).toBeVisible();

    await page.goto(`${APP_BASE}/agenda?saved=1`);
    await waitForLiveView(page);
    await expect(page.getByText("E2E Opening Keynote")).toBeVisible();
    await expect(page.getByText("E2E Evening Reception")).not.toBeVisible();

    await page.locator(".ngs-save-button").first().click();
    await expect(page.getByText("Session removed.")).toBeVisible();
  });

  test("opens session detail with local time and resources section", async ({ page }) => {
    await page.goto(`${APP_BASE}/agenda`);
    await page.click('a:has-text("E2E Opening Keynote")');

    await expect(page.getByRole("heading", { name: "E2E Opening Keynote" })).toBeVisible();
    await expect(page.getByText("08:30")).toBeVisible();
    await expect(page.getByText("Main Stage").first()).toBeVisible();
    await expectNoHorizontalOverflow(page);
  });
});
