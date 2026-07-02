import { test as setup } from "@playwright/test";
import * as fs from "node:fs";
import * as path from "node:path";
import { seed, signInAttendee, signInOwner, ATTENDEE_STATE, OWNER_STATE } from "./helpers";

setup("seed the e2e event and capture auth states", async ({ browser }) => {
  setup.setTimeout(300_000);

  seed();
  fs.mkdirSync(path.dirname(ATTENDEE_STATE), { recursive: true });

  const attendeeContext = await browser.newContext();
  const attendeePage = await attendeeContext.newPage();
  await signInAttendee(attendeePage);
  await attendeeContext.storageState({ path: ATTENDEE_STATE });
  await attendeeContext.close();

  const ownerContext = await browser.newContext();
  const ownerPage = await ownerContext.newPage();
  await signInOwner(ownerPage);
  await ownerContext.storageState({ path: OWNER_STATE });
  await ownerContext.close();
});
