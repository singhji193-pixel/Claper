import { test, expect, Browser, Page } from "@playwright/test";
import {
  APP_BASE,
  EVENT_CODE,
  ATTENDEE_STATE,
  OWNER_STATE,
  waitForLiveView,
} from "./helpers";

/**
 * Manager <-> PWA bridge audit. Every test drives the real organizer manage
 * UI in one context and asserts the propagated result in a connected
 * attendee PWA context (no reloads). Serial: tests share the live event
 * state and each one restores what it flips.
 */
test.describe.configure({ mode: "serial" });

async function openPair(browser: Browser): Promise<{ attendee: Page; owner: Page; close: () => Promise<void> }> {
  const attendeeContext = await browser.newContext({ storageState: ATTENDEE_STATE });
  const ownerContext = await browser.newContext({ storageState: OWNER_STATE });
  const attendee = await attendeeContext.newPage();
  const owner = await ownerContext.newPage();

  await attendee.goto(`${APP_BASE}/live`);
  await waitForLiveView(attendee);
  await owner.goto(`/e/${EVENT_CODE}/manage`);
  await waitForLiveView(owner);

  return {
    attendee,
    owner,
    close: async () => {
      await attendeeContext.close();
      await ownerContext.close();
    },
  };
}

async function setInteraction(owner: Page, title: string, state: "Enable" | "Disable") {
  await owner
    .locator("#interactions div")
    .filter({ hasText: title })
    .filter({ has: owner.locator(`button:has-text("${state}")`) })
    .last()
    .locator(`button:has-text("${state}")`)
    .first()
    .click();
}

test.describe("manager to PWA bridge", () => {
  test("quiz: enable in manage, attendee submits, sees results, disable restores poll", async ({ browser }) => {
    const { attendee, owner, close } = await openPair(browser);
    try {
      await setInteraction(owner, "E2E summit quiz", "Enable");

      await expect(attendee.getByText("Where is the summit held?")).toBeVisible({ timeout: 15_000 });
      await attendee.locator('.ngs-live-option:has-text("Anvil Centre") input').check();
      await attendee.locator('form[id^="pwa-live-quiz-form"] button[type="submit"]').click();
      // show_results: true -> response counts come back and options lock.
      const quizForm = attendee.locator('form[id^="pwa-live-quiz-form"]');
      await expect(quizForm.locator('.ngs-live-option:has-text("Anvil Centre")')).toContainText("1", { timeout: 15_000 });
      await expect(quizForm.locator('.ngs-live-option input').first()).toBeDisabled();

      // Disabling flips the live card into the 30-minute "Latest result" state.
      await setInteraction(owner, "E2E summit quiz", "Disable");
      await expect(attendee.getByText("Latest result")).toBeVisible({ timeout: 15_000 });
      await expect(attendee.getByText("Closed")).toBeVisible();
    } finally {
      await close();
    }
  });

  test("form: enable in manage, attendee submits, submission reaches manager list", async ({ browser }) => {
    const { attendee, owner, close } = await openPair(browser);
    try {
      await setInteraction(owner, "E2E feedback form", "Enable");

      await expect(attendee.getByText("E2E feedback form")).toBeVisible({ timeout: 15_000 });
      await attendee.fill('input[name="response[Full name]"]', "Emery Tester");
      await attendee.fill('input[name="response[Work email]"]', "emery@example.com");
      await attendee.locator('form[id^="pwa-live-form"] button[type="submit"]').click();
      await expect(attendee.getByText("Update response")).toBeVisible({ timeout: 15_000 });

      await owner.getByText("Form submissions", { exact: false }).click();
      await expect(owner.locator("#form-list")).toContainText("Emery Tester", { timeout: 15_000 });

      await setInteraction(owner, "E2E feedback form", "Disable");
    } finally {
      await close();
    }
  });

  test("embed: enable in manage, attendee sees sandboxed inline content", async ({ browser }) => {
    const { attendee, owner, close } = await openPair(browser);
    try {
      await setInteraction(owner, "E2E highlight reel", "Enable");

      await expect(attendee.getByText("E2E highlight reel")).toBeVisible({ timeout: 15_000 });
      const iframe = attendee.locator(".ngs-live-embed iframe");
      await expect(iframe).toBeVisible();
      await expect(iframe).toHaveAttribute("sandbox", /allow-scripts/);

      await setInteraction(owner, "E2E highlight reel", "Disable");
      await expect(attendee.getByText("E2E highlight reel")).not.toBeVisible({ timeout: 15_000 });
    } finally {
      await close();
    }
  });

  test("moderation: pin + pinned-only filters chat but not Q&A, delete removes live", async ({ browser }) => {
    const { attendee, owner, close } = await openPair(browser);
    try {
      // Two chat messages and one question from the attendee.
      await attendee.click('.ngs-live-tab:has-text("Chat")');
      await attendee.fill('#pwa-live-message-form textarea', "Bridge keep me");
      await attendee.locator('#pwa-live-message-form button[type="submit"]').click();
      await expect(attendee.getByText("Bridge keep me")).toBeVisible();
      await attendee.fill('#pwa-live-message-form textarea', "Bridge hide me");
      await attendee.locator('#pwa-live-message-form button[type="submit"]').click();
      await expect(attendee.getByText("Bridge hide me")).toBeVisible();

      await attendee.click('.ngs-live-tab:has-text("Q&A")');
      await attendee.fill('#pwa-live-question-form textarea', "Bridge question stays");
      await attendee.locator('#pwa-live-question-form button[type="submit"]').click();
      await expect(attendee.getByText("Bridge question stays")).toBeVisible();

      // Manager pins the first message.
      await owner.locator('div[id^="posts-"]:has-text("Bridge keep me")').getByText("Pin", { exact: true }).click();

      // Presenter setting: show only pinned (key "e" toggle in settings panel).
      // Rendered twice (settings modal + inline panel); act on the visible one.
      const pinnedOnly = owner.locator('button[phx-value-key="show_only_pinned"]:visible');
      await pinnedOnly.click();

      // Attendee chat lane: only the pinned post remains; Q&A untouched.
      await attendee.click('.ngs-live-tab:has-text("Chat")');
      await expect(attendee.getByText("Bridge hide me")).not.toBeVisible({ timeout: 15_000 });
      await expect(attendee.getByText("Bridge keep me")).toBeVisible();
      await attendee.click('.ngs-live-tab:has-text("Q&A")');
      await expect(attendee.getByText("Bridge question stays")).toBeVisible();

      // Restore, then manager deletes a message and it vanishes live.
      await pinnedOnly.click();
      await attendee.click('.ngs-live-tab:has-text("Chat")');
      await expect(attendee.getByText("Bridge hide me")).toBeVisible({ timeout: 15_000 });

      owner.on("dialog", (dialog) => dialog.accept());
      await owner.locator('div[id^="posts-"]:has-text("Bridge hide me")').getByText("Delete", { exact: true }).click();
      await expect(attendee.getByText("Bridge hide me")).not.toBeVisible({ timeout: 15_000 });
    } finally {
      await close();
    }
  });

  test("ban: manager ban blocks the PWA attendee and deletes their posts", async ({ browser }) => {
    const { attendee, owner, close } = await openPair(browser);
    try {
      await attendee.click('.ngs-live-tab:has-text("Chat")');
      await attendee.fill('#pwa-live-message-form textarea', "Bridge ban me");
      await attendee.locator('#pwa-live-message-form button[type="submit"]').click();
      await expect(attendee.getByText("Bridge ban me")).toBeVisible();

      owner.on("dialog", (dialog) => dialog.accept());
      await owner.locator('div[id^="posts-"]:has-text("Bridge ban me")').getByText("Ban", { exact: true }).click();

      // Attendee loses live participation without reload; posts are gone.
      await expect(attendee.getByText("Live participation unavailable")).toBeVisible({ timeout: 15_000 });
      await expect(attendee.getByText("Bridge ban me")).not.toBeVisible();

      // Unban by clearing state directly (no UI exists for unban).
      const { execSync } = require("node:child_process");
      execSync(
        `docker exec clapper-db-1 psql -U claper -d claper -c "UPDATE presentation_states SET banned = '{}' WHERE presentation_file_id IN (SELECT id FROM presentation_files WHERE event_id = (SELECT id FROM events WHERE code = '${EVENT_CODE}'))"`,
        { stdio: "inherit", timeout: 30_000 }
      );
    } finally {
      await close();
    }
  });

  test("classic room: anonymous visitor reaches the same event without any gate", async ({ browser }) => {
    // Documents the PWA/classic authorization asymmetry: /e/:code is open.
    const anonContext = await browser.newContext();
    const anon = await anonContext.newPage();
    try {
      await anon.goto(`/e/${EVENT_CODE}`);
      await waitForLiveView(anon);
      // No OTP gate: the anonymous visitor lands in the event room (pre-start it
      // is the countdown/join screen; once started_at passes, the composer and
      // polls are open to anyone holding the code).
      await expect(anon).toHaveURL(new RegExp(`/e/${EVENT_CODE}`));
      await expect(anon.getByRole("heading", { name: "NextGen E2E Summit" })).toBeVisible({ timeout: 15_000 });
    } finally {
      await anonContext.close();
    }
  });
});
