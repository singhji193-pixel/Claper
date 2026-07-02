import { test, expect } from "@playwright/test";
import { APP_BASE, ATTENDEE_STATE, expectNoHorizontalOverflow } from "./helpers";

test.use({ storageState: ATTENDEE_STATE });

test.describe("ticket wallet", () => {
  test("renders the pass with a Hi.Events-scannable QR payload", async ({ page }) => {
    await page.goto(`${APP_BASE}/ticket`);

    await expect(page.getByText("Emery Tester").first()).toBeVisible();
    await expect(page.getByText("Builder Pass").first()).toBeVisible();

    // The QR must encode the Hi.Events attendee public_id so the door
    // check-in scanner resolves the attendee.
    const qr = page.locator("#pwa-ticket-qr");
    await expect(qr).toHaveAttribute("data-url", "e2e-public-1");

    await expectNoHorizontalOverflow(page);
  });
});
