# CoreOrbit Ask (Rebranded Claper)

A white-labeled version of [Claper](https://github.com/ClaperCo/Claper) — an open-source audience interaction tool for live events, rebranded as **CoreOrbit Ask**.

**Live URL:** https://ask.coreorbit.io
**Fork:** https://github.com/singhji193-pixel/Claper (branch: `coreorbit-ask`)
**Upstream:** https://github.com/ClaperCo/Claper (branch: `dev`)

---

## Branding Summary

| Element | Before (Claper) | After (CoreOrbit Ask) |
|---------|-----------------|----------------------|
| App Name | Claper | CoreOrbit Ask |
| Domain | claper.co | coreorbit.io / ask.coreorbit.io |
| Primary Color | #1186D5 (blue) | #f15a24 (orange) |
| Accent Color | #8611ed / #A327FF (purple) | #f15a24 / #ff6b35 (orange) |
| Gradient | Blue-to-Purple | Orange-to-DeepOrange |
| Logo (dark bg) | Claper white logo | CoreOrbit white logo (logo-large.png) |
| Logo (headers) | Claper icon | Orange "Ci" favicon (logo.png) |
| Hamburger Logo | Claper logo | HQ CoreOrbit logo (hq-logo.png) |
| Favicon | Claper icon | Orange "Ci" (favicon.png) |

---

## Complete List of Changes

### 1. CSS / Theme Files

#### `assets/css/theme.css` (FULL REWRITE)
- Complete Tailwind CSS @theme rewrite
- Primary palette: `#f15a24` based (50-950 shades)
- Secondary palette: deeper orange variants
- Dark/neutral colors left unchanged

#### `assets/css/admin.css`
- DaisyUI theme name: `"claper"` -> `"coreorbit"`
- `--color-accent`: `#8611ed` -> `#f15a24`
- `--color-secondary`: `#6b21a8` -> `#d94a1a`

#### `assets/css/modern.css`
- `--color-sky-blue`: `#1186D5` -> `#f15a24`
- `--color-azure`: `#0C6EAB` -> `#d94a1a`
- `--color-mauve`: `#7B2FD4` -> `#ff6b35`
- `--color-purple`: `#A327FF` -> `#f57d4a`
- `--color-teal`: `#0E8784` -> `#b53b14`

### 2. Audience View (`lib/claper_web/live/event_live/show.html.heex`)

- **Hamburger menu logo**: `/images/logo-large.png` -> `/images/hq-logo.png` (class `h-20`)
- **Message input gradient** (3 instances - nickname form, post form, disabled state):
  - `rgba(17,134,213,0.50)` -> `rgba(241,90,36,0.50)`
  - `rgba(163,39,255,0.50)` -> `rgba(255,107,53,0.50)`
- **Banner link**: `https://claper.co` -> `https://coreorbit.io`
- **Banner text**: `"Claper"` -> `"CoreOrbit Ask"`
- All hardcoded `#1186D5`, `#A327FF` hex colors -> orange equivalents

### 3. Join Page (`lib/claper_web/live/event_live/join.html.heex`)

- **Logo**: `/images/logo.png` (h-12) -> `/images/logo-large.png` (h-36, white CoreOrbit)
- **"About" links** (2x): `https://get.claper.co/` -> `https://coreorbit.io`

### 4. Login Page (`lib/claper_web/templates/user_session/new.html.heex`)

- **Left panel** (dark bg with photo): shows `logo-large.png` (white CoreOrbit logo)
- **Right panel** (form side): shows `logo.png` (orange Ci favicon)

### 5. Layout Templates

#### `lib/claper_web/templates/layout/root.html.heex`
- `<.live_title suffix=" . Claper">` -> `" . CoreOrbit Ask"`

#### `lib/claper_web/templates/layout/admin.html.heex`
- Title: `"Claper Admin"` -> `"CoreOrbit Ask Admin"`
- Logo references: all -> `.png` versions
- `docs.claper.co` link -> `ask.coreorbit.io`

#### `lib/claper_web/templates/layout/user.html.heex`
- Title suffix: `" . Claper"` -> `" . CoreOrbit Ask"`

#### All layouts with logo references
- `/images/logo.svg` -> `/images/logo.png`
- `/images/logo-large.svg` -> `/images/logo-large.png`
- `/images/logo-large-black.svg` -> `/images/logo-large.png`
- `/images/logo-white.svg` -> `/images/logo-large.png`

### 6. Email Templates

All 4 email templates in `lib/claper_web/templates/user_notifier/`:
- `change.html.heex`
- `magic.html.heex`
- `reset.html.heex`
- `confirm.html.heex`

Changes:
- CTA button background: `#8611ed` -> `#f15a24`
- "Claper team" -> "CoreOrbit Ask team"
- `claper.co` -> `coreorbit.io`

#### `lib/claper_web/templates/layout/email.html.heex`
- `alt="Claper"` -> `alt="CoreOrbit Ask"`

#### `lib/claper_web/notifiers/user_notifier.ex`
- Email subject: `"Connect to Claper"` -> `"Connect to CoreOrbit Ask"`

### 7. LTI Integration

#### `lib/claper_web/controllers/lti/registration_controller.ex`
- `"client_name" => "Claper"` -> `"CoreOrbit Ask"`

#### `lib/claper_web/templates/lti/` (all .heex files)
- All visible "Claper" text -> "CoreOrbit Ask"

### 8. Error Pages

- `lib/claper_web/templates/error/404.html.heex`
- `lib/claper_web/templates/error/500.html.heex`
- `lib/claper_web/templates/error/csrf_error.html.heex`
- All "Claper" -> "CoreOrbit Ask"

### 9. Static/Legal Pages

- `lib/claper_web/templates/page/privacy.html.heex` - "Claper" -> "CoreOrbit Ask"
- `lib/claper_web/templates/page/tos.html.heex` - "Claper" -> "CoreOrbit Ask"

### 10. Gettext Translations (all languages)

All `.po` files in `priv/gettext/` (de, en, es, fr, hu, it, lv, nl):
- All `msgstr` and `msgid` containing "Claper" -> "CoreOrbit Ask"

### 11. Event Index (Dashboard)

#### `lib/claper_web/live/event_live/index.html.heex`
- Tour text: "Welcome to Claper" -> "Welcome to CoreOrbit Ask"

### 12. Docker Configuration

#### `docker-compose.yml`
- Image: `ghcr.io/claperco/claper:latest` -> `coreorbit-ask:latest`

---

## Image/Logo Files

| File | Description | Source |
|------|-------------|--------|
| `priv/static/images/logo-large.png` | White CoreOrbit logo (for dark backgrounds, login, join) | white log email header (2).png |
| `priv/static/images/logo.png` | Orange "Ci" favicon (for headers, right panel) | final favicon.png |
| `priv/static/images/favicon.png` | Same orange "Ci" favicon | final favicon.png |
| `priv/static/images/hq-logo.png` | Full color CoreOrbit logo with tagline (hamburger menu) | HQ Logo.png |
| `assets/images/` | Copies of above for build process | Same files |

---

## Environment Configuration (.env)

```env
BASE_URL=https://ask.coreorbit.io
DATABASE_URL=postgres://claper:claper@db:5432/claper
SECRET_KEY_BASE=<generated-64-char-key>
MAIL_TRANSPORT=smtp
MAIL_FROM=events@coreorbit.io
MAIL_FROM_NAME=CoreOrbit Ask
SMTP_RELAY=smtp.elasticemail.com
SMTP_USERNAME=events@coreorbit.io
SMTP_PASSWORD=<elastic-email-api-key>
SMTP_PORT=2525
ENABLE_ACCOUNT_CREATION=false
EMAIL_CONFIRMATION=false
```

---

## Deployment

### Build and Run
```bash
cd /opt/claper
docker build -t coreorbit-ask:latest .
docker compose up -d
```

### Rebuild after source changes (with cache)
```bash
docker build -t coreorbit-ask:latest .
docker compose up -d --force-recreate
```

### Full rebuild (no cache - takes 3-5 min)
```bash
docker build --no-cache -t coreorbit-ask:latest .
docker compose down && docker compose up -d
```

---

## How to Re-apply Branding After Upstream Update

If you pull updates from upstream and branding is lost:

1. **Rebase approach** (recommended):
   ```bash
   git fetch origin
   git rebase origin/dev
   # Resolve conflicts in branded files
   docker build --no-cache -t coreorbit-ask:latest .
   docker compose up -d --force-recreate
   ```

2. **Cherry-pick approach**:
   ```bash
   git fetch origin
   git checkout origin/dev
   git checkout -b coreorbit-ask-v2
   git cherry-pick <commit-hash-of-rebrand>
   # Fix conflicts
   docker build --no-cache -t coreorbit-ask:latest .
   ```

3. **Manual re-apply** (nuclear option):
   - Run the `rebrand_comprehensive.py` script
   - Re-upload logo files from `assets/images/`
   - Rebuild Docker image

---

## Files NOT Changed (Important - DO NOT TOUCH)

These contain "Claper" but are **Elixir module names** that MUST NOT be renamed:
- `ClaperWeb` (Elixir module namespace)
- `Claper.Repo`, `Claper.Accounts`, `Claper.Events`, etc.
- `claper_web` (directory/file paths)
- `Application.get_env(:claper, ...)` (OTP app config keys)
- `claperco` (in original upstream URL)
- Database name `claper` in DATABASE_URL

Changing any of these will **break compilation**.

---

## Color Reference

### Orange Palette (#f15a24 base)
```
Primary-50:  #fff5f0
Primary-100: #ffe8dd
Primary-200: #ffd0ba
Primary-300: #ffab85
Primary-400: #f57d4a
Primary-500: #f15a24  <-- BASE
Primary-600: #d94a1a
Primary-700: #b53b14
Primary-800: #8c2e10
Primary-900: #6b240d
Primary-950: #3d1307
```

### Dark Backgrounds (UNCHANGED - do not modify)
```
Join page: #2C033A, #21033A, #053138
Login page: black
Admin: DaisyUI dark theme
Audience view: black
```

---

## Reverse Proxy (Caddy)

The app runs on port 4000 and is proxied via Caddy at `ask.coreorbit.io`:
- SSL: auto via Caddy (Let's Encrypt)
- Proxy: `localhost:4000`
- WebSocket support: enabled (required for Phoenix LiveView)

---

## Default Admin Login

- **Email:** admin@claper.co
- **Password:** claper
- **IMPORTANT:** Change this immediately after first login

---

## Server Info

- **VPS:** 82.180.137.121
- **OS:** Ubuntu (Docker host)
- **CPU:** 4-core AMD EPYC
- **RAM:** 16GB
- **Path:** /opt/claper
- **Branch:** coreorbit-ask
- **Docker image:** coreorbit-ask:latest
