# NextGen Summit PWA E2E Suite

Playwright end-to-end tests for the attendee PWA, run against the local dev
server (`clapper-app-1` Docker container on `http://localhost:4000`).

## Prerequisites

- `clapper-app-1` and `clapper-db-1` containers running (`docker compose up`)
- Node 18+ on the host

## Setup

```bash
cd e2e
npm install
npx playwright install chromium
```

## Running

```bash
cd e2e
npx playwright test            # all projects (mobile + desktop)
npx playwright test --project=mobile
npx playwright test tests/auth.spec.ts
npx playwright show-report
```

The `setup` project reseeds a dedicated `e2e01` event before each run via
`e2e/seed.exs` (owner `e2e-owner@example.com`, attendee
`e2e-attendee@example.com`, ticket public_id `e2e-public-1`). Only the
`e2e01` event is deleted and recreated; no other local data is touched.

OTP delivery is not required: `e2e/otp.exs` swaps the attendee's pending
challenge for a deterministic `4821` code after the login form is submitted,
so the real login/verify screens are still exercised.

## Coverage (P0)

- OTP auth: gate redirects with `next`, unknown ticket email, wrong/right
  code, next-path preservation, session persistence, sign-out
- Agenda: event-local times (UTC storage), single-day grouping across UTC
  midnight, track filter, search, save/unsave, session detail
- Ticket wallet: pass rendering, QR payload equals the Hi.Events attendee
  `public_id`
- Live bridge: poll submit + locked state, Q&A post, chat post, reaction
  toggle, organizer feature-flag flip reaching a connected attendee without
  reload
- Legacy Claper routes: `/e/:code`, `/e/:code/agenda`, `/e/:code/bingo`

Never point this suite at production; it deletes and reseeds the `e2e01`
event and rewrites OTP challenges.
