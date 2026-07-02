# PWA Live Section UI Redesign — Design Spec

Date: 2026-07-02
Status: approved (user: "PROCEED")
Direction: premium calm + single live accent, inside the existing NextGen
light palette (parchment/ink/gold). Server logic, routes, LiveView event
names, form ids, validation, and rate limits are unchanged.

## Problems (observed via 375px screenshots at commit 2848653)

1. Live surfaces request icon names missing from `ngs_icon` — every one
   renders the `+` fallback (home live card, banner, Q&A/Chat headers,
   empty states, poll kind chip).
2. Home shows two stacked live entries (LIVE NOW card + compact banner).
3. Poll results are plain-text percentages; selected vs unselected options
   are nearly identical gold blocks.
4. Q&A/Chat posts are generic cards: no timestamps, no own-message
   distinction, no avatars; three always-visible zero-count reaction pills.
5. Header "Active" pill uses a ticket icon; no live affordance anywhere
   (no pulse/dot).
6. Large dead space on sparse panels.

## Changes

### Foundation
- Add missing icons to `ngs_icon` (same 1.8-stroke family): chart-bar,
  light-bulb, bolt, signal-slash, no-symbol, arrow-path,
  question-mark-circle, chat-bubble-left-right, play-circle, document-text,
  plus paper-airplane and hand-thumb-up for composer/upvote.
- New semantic token `--ngs-live` (warm signal red, AA on parchment) used
  only for the live dot and LIVE badges. Shared `ngs-pulse` keyframe,
  disabled under `prefers-reduced-motion`.

### Home entry
- Live card: pulsing dot + "LIVE" eyebrow, interaction-kind icon, title,
  chevron CTA.
- Compact banner no longer renders on the home action (template condition
  `@live_action != :home`); other routes keep it, restyled as a slim pill
  with the pulse dot. The 5.17 bottom content reserve stays.

### Live screen chrome
- Header pill becomes a LIVE badge (dot + "Live now") when an interaction
  is active.
- Tabs: identical ids/events; Q&A and Chat tabs show count badges from the
  snapshot lists.

### Interact panel
- Poll options render result bars: champagne track, gold fill sized by the
  existing `percentage` value, tabular-nums percentage, selected = ink
  border + check, quiz correct = green + check.
- Unsubmitted options: white rows, visible control, press scale feedback.
- Empty/closed states vertically centered in the panel.

### Q&A / Chat
- Slim count row replaces the large header block.
- Posts: initials avatar (derived from `post.name` in the template), name,
  HH:MM timestamp in the event timezone, body.
- Chat: own messages (`mine`) right-aligned champagne bubbles labeled
  "You"; others left-aligned white bubbles.
- Reactions: all three buttons remain (same events, same `is-active`
  class); zero-count buttons render icon-only ghost pills; counts appear
  only when > 0. Global reaction row tightens into the composer with a
  tap scale-pop.
- Chat/Q&A lane auto-scrolls to the newest post via a new `ScrollBottom`
  JS hook (the only new JavaScript).

### Read-only snapshot additions
`LiveInteractions` public posts gain:
- `inserted_at` (naive UTC; formatted per event timezone in the template)
- `mine` (server-side `attendee_identifier == interaction_key`; the key is
  never exposed)
Both additive; every existing field is untouched.

## Testing
- TDD context tests for `inserted_at` and `mine` in post snapshots.
- LiveView tests: own-message bubble class, rendered timestamp.
- Full event LiveView suite + full mix suite.
- E2E `live.spec.ts` re-run; fresh 375px screenshots for visual review.

## Out of scope
Sorting/moderation features, presenter views, People/Bingo surfaces,
banner reserve mechanics, any event or id rename.
