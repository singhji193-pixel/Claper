import { execSync } from "node:child_process";
import * as path from "node:path";
import { Page, expect } from "@playwright/test";

export const EVENT_CODE = "e2e01";
export const APP_BASE = `/app/${EVENT_CODE}`;
export const OTP_CODE = "4821";
export const OWNER_EMAIL = "e2e-owner@example.com";
export const OWNER_PASSWORD = "e2e-password-123";
export const ATTENDEE_EMAIL = "e2e-attendee@example.com";

export const ATTENDEE_STATE = path.join(__dirname, "..", ".auth", "attendee.json");
export const OWNER_STATE = path.join(__dirname, "..", ".auth", "owner.json");

/** Reseeds the dedicated e2e01 event. Call once per run from global setup. */
export function seed(): void {
  execSync("docker exec clapper-app-1 mix run e2e/seed.exs", {
    stdio: "inherit",
    timeout: 180_000,
  });
}

/**
 * Replaces the attendee's pending OTP challenge with a deterministic code so
 * the browser flow can complete without email delivery. Slow (~20s): it boots
 * the app inside the container, so prefer the saved storage states for tests
 * that only need an authenticated session.
 */
export function prepareOtp(email: string, code: string = OTP_CODE): void {
  execSync(`docker exec clapper-app-1 mix run e2e/otp.exs ${email} ${code}`, {
    stdio: "inherit",
    timeout: 180_000,
  });
}

/**
 * Waits until the LiveView socket has joined; phx-click/submit/change events
 * silently no-op before that, so socket-dependent tests must call this after
 * navigation.
 */
export async function waitForLiveView(page: Page): Promise<void> {
  await page.waitForSelector("[data-phx-main].phx-connected", { timeout: 30_000 });
}

/** Navigation that tolerates LiveView auth redirects aborting the initial load. */
export async function gotoExpectingRedirect(page: Page, url: string, target: RegExp): Promise<void> {
  await page.goto(url, { waitUntil: "commit" }).catch(() => {});
  await page.waitForURL(target);
}

/**
 * Deletes pending OTP challenges directly in the dev database so the 60s
 * request-spacing rule never rejects the next login form submit. Fast
 * (plain psql) compared to booting the app via mix run.
 */
export function clearOtpChallenges(email: string): void {
  execSync(
    `docker exec clapper-db-1 psql -U claper -d claper -c "DELETE FROM event_app_otp_challenges WHERE email = '${email}'"`,
    { stdio: "inherit", timeout: 30_000 }
  );
}

/** Full attendee OTP sign-in through the real login and verify screens. */
export async function signInAttendee(page: Page, email: string = ATTENDEE_EMAIL): Promise<void> {
  clearOtpChallenges(email);
  await page.goto(`${APP_BASE}/login`);
  await page.fill('input[name="attendee[email]"]', email);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/verify/);

  prepareOtp(email);

  await page.fill('input[name="attendee[code]"]', OTP_CODE);
  await page.click('button[type="submit"]');
  await page.waitForURL((url) => !url.pathname.includes("/verify") && !url.pathname.includes("/login"));
}

/**
 * Owner sign-in to the Claper organizer backend. The post-login redirect to
 * /events can error in dev for fresh users, but the session cookie is set
 * either way, so verify auth by loading the protected manage route instead.
 */
export async function signInOwner(page: Page): Promise<void> {
  await page.goto("/users/log_in");
  await page.fill('input[name="user[email]"]', OWNER_EMAIL);
  await page.fill('input[name="user[password]"]', OWNER_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForLoadState("domcontentloaded");

  await page.goto(`/e/${EVENT_CODE}/manage/app`);
  await page.waitForURL(new RegExp(`/e/${EVENT_CODE}/manage/app`));
}

export async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  expect(overflow).toBeLessThanOrEqual(0);
}
