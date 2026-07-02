import { test, expect } from "@playwright/test";
import {
  APP_BASE,
  ATTENDEE_EMAIL,
  OTP_CODE,
  clearOtpChallenges,
  gotoExpectingRedirect,
  prepareOtp,
  signInAttendee,
} from "./helpers";

test.describe("attendee OTP auth", () => {
  // Each OTP round-trip shells into the container (~20s); allow headroom.
  test.slow();

  test("redirects every signed-out PWA route to login with a next path", async ({ page }) => {
    const loginUrl = new RegExp(`${APP_BASE}/login\\?next=`);

    for (const route of ["", "/agenda", "/ticket", "/profile", "/live"]) {
      await gotoExpectingRedirect(page, `${APP_BASE}${route}`, loginUrl);
    }
  });

  test("rejects an unknown ticket email", async ({ page }) => {
    await page.goto(`${APP_BASE}/login`);
    await page.fill('input[name="attendee[email]"]', "nobody@example.com");
    await page.click('button[type="submit"]');
    await expect(page.getByText("No active ticket was found")).toBeVisible();
  });

  test("rejects a wrong OTP code and accepts the right one", async ({ page }) => {
    clearOtpChallenges(ATTENDEE_EMAIL);
    await page.goto(`${APP_BASE}/login`);
    await page.fill('input[name="attendee[email]"]', ATTENDEE_EMAIL);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/verify/);

    prepareOtp(ATTENDEE_EMAIL);

    await page.fill('input[name="attendee[code]"]', "0000");
    await page.click('button[type="submit"]');
    await expect(page.getByText("That code is not correct")).toBeVisible();

    await page.fill('input[name="attendee[code]"]', OTP_CODE);
    await page.click('button[type="submit"]');
    await page.waitForURL((url) => !url.pathname.includes("/verify"));
    await expect(page.getByText("You are signed in.")).toBeVisible();
  });

  test("preserves the requested page through login", async ({ page }) => {
    clearOtpChallenges(ATTENDEE_EMAIL);
    await gotoExpectingRedirect(
      page,
      `${APP_BASE}/agenda`,
      new RegExp(`${APP_BASE}/login\\?next=`)
    );

    await page.fill('input[name="attendee[email]"]', ATTENDEE_EMAIL);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/verify/);

    prepareOtp(ATTENDEE_EMAIL);

    await page.fill('input[name="attendee[code]"]', OTP_CODE);
    await page.click('button[type="submit"]');
    await page.waitForURL(new RegExp(`${APP_BASE}/agenda`));
  });

  test("session persists across a reload and sign-out clears it", async ({ page }) => {
    await signInAttendee(page);

    await page.goto(`${APP_BASE}/profile`);
    await expect(page).toHaveURL(new RegExp(`${APP_BASE}/profile`));

    await page.reload();
    await expect(page).toHaveURL(new RegExp(`${APP_BASE}/profile`));

    // Sign out via the profile action, then a protected route redirects again.
    await page.click('button:has-text("Sign out"), a:has-text("Sign out")');
    await gotoExpectingRedirect(
      page,
      `${APP_BASE}/ticket`,
      new RegExp(`${APP_BASE}/login\\?next=`)
    );
  });
});
