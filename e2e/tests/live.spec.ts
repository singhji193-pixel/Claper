import { test, expect } from "@playwright/test";
import { APP_BASE, EVENT_CODE, ATTENDEE_STATE, OWNER_STATE, waitForLiveView } from "./helpers";

test.describe("native live bridge", () => {
  test.use({ storageState: ATTENDEE_STATE });

  test("attendee submits the active poll and sees a locked state", async ({ page }) => {
    await page.goto(`${APP_BASE}/live`);
    await waitForLiveView(page);

    await expect(page.getByText("E2E favourite track?")).toBeVisible();

    await page.locator('.ngs-live-option:has-text("Growth") input').check();
    await page.locator('form[id^="pwa-live-poll-form"] button[type="submit"]').click();

    // Exact match: the reconnect banner also contains the word "submitted".
    await expect(page.getByText("Submitted", { exact: true })).toBeVisible();

    // Reload restores the locked answer from the server.
    await page.reload();
    await waitForLiveView(page);
    await expect(page.getByText("Submitted", { exact: true })).toBeVisible();
  });

  test("attendee posts a question and a chat message with a reaction", async ({ page }) => {
    await page.goto(`${APP_BASE}/live`);
    await waitForLiveView(page);

    await page.click('.ngs-live-tab:has-text("Q&A")');
    await page.fill("#pwa-live-question-form textarea", "E2E question: when is lunch?");
    await page.locator("#pwa-live-question-form button[type='submit']").click();
    await expect(page.getByText("E2E question: when is lunch?")).toBeVisible();

    await page.click('.ngs-live-tab:has-text("Chat")');
    await page.fill("#pwa-live-message-form textarea", "E2E hello from the chat lane");
    await page.locator("#pwa-live-message-form button[type='submit']").click();
    await expect(page.getByText("E2E hello from the chat lane")).toBeVisible();

    const reaction = page.locator('button[phx-click="live-toggle-reaction"]').first();
    await reaction.click();
    await expect(reaction).toHaveClass(/is-active/);
  });

  test("organizer flag flip reaches a connected attendee without reload", async ({ browser }) => {
    const attendeeContext = await browser.newContext({ storageState: ATTENDEE_STATE });
    const ownerContext = await browser.newContext({ storageState: OWNER_STATE });
    const attendee = await attendeeContext.newPage();
    const owner = await ownerContext.newPage();

    try {
      await attendee.goto(`${APP_BASE}/live`);
      await waitForLiveView(attendee);
      await expect(attendee.getByText("E2E favourite track?")).toBeVisible();

      await owner.goto(`/e/${EVENT_CODE}/manage/app`);
      await waitForLiveView(owner);

      const liveToggle = owner.locator(
        'input[name="setting[live_interactions_enabled]"][type="checkbox"]'
      );
      await liveToggle.uncheck();
      await expect(owner.getByText("Changes saved")).toBeVisible();

      // The already-connected attendee loses the live surface without reloading.
      await expect(attendee.getByText("E2E favourite track?")).not.toBeVisible({
        timeout: 15_000,
      });

      await liveToggle.check();
      await expect(owner.getByText("Changes saved")).toBeVisible();
      await expect(attendee.getByText("E2E favourite track?")).toBeVisible({ timeout: 15_000 });
    } finally {
      await attendeeContext.close();
      await ownerContext.close();
    }
  });
});
