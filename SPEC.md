# claude-pulse — Spec

> **Architecture note (current, as shipped).** This document records the design history,
> including two data-source approaches that were explored and then replaced. The shipped
> design is **keychain-free**: accounts are discovered from plaintext `~/.claude*/.claude.json`,
> usage is read from the `anthropic-ratelimit-unified-*` headers of a 1-token `/v1/messages`
> request (using a user-pasted `claude setup-token` stored in a 0600 file), and polling is
> activity-gated. The earlier sections describing macOS Keychain reads and the
> `/api/oauth/usage` and `/api/oauth/profile` endpoints are **superseded** — see README.md
> for the authoritative how-it-works. Reasons they were dropped: the Keychain prompt could
> not be made to persist for a self-signed app, and `setup-token` lacks the scope for the
> `/oauth/*` endpoints (403) but works for inference (whose response headers carry the
> windows).

## Summary

A native macOS utility that shows Claude Code subscription usage for **both** of the user's subscriptions — Personal (Max x20, `~/.claude`) and Team/Enterprise (`~/.claude-team`) — in two surfaces:

1. A **menubar item** (always visible compact usage; click → popover with full claude.ai-style detail).
2. A **native macOS widget** (WidgetKit) showing 5-hour session usage + reset time and weekly usage + reset time for both subscriptions.

Post-MVP: predict when the 5-hour and weekly windows will hit 100% based on recent usage rate.

## Design decisions

- **Stack: all Swift/SwiftUI.** One app target (`ClaudePulse`, menubar via `MenuBarExtra`, `LSUIElement`) + one WidgetKit extension target (`ClaudePulseWidget`). A true macOS widget is WidgetKit-only; adding a TypeScript layer would mean two toolchains for no benefit. *(User confirmed.)*
- **Data source: the OAuth usage endpoint**, not transcript parsing. `GET https://api.anthropic.com/api/oauth/usage` returns exactly what claude.ai shows (verified by community usage, see Key facts). Transcript-based estimation (ccusage-style) is inaccurate and misses usage from other devices; the Admin API does not expose these windows at all.
- **Credentials: read-only.** Tokens are read from the macOS Keychain entries Claude Code maintains. **The app NEVER refreshes tokens** — Anthropic refresh tokens rotate (single-use); a third-party refresh would log Claude Code out. *(User directive.)* If a token is expired, the app shows the last snapshot marked stale with a "open Claude Code to refresh" hint.
- **Widget gets data via a snapshot file written by the menubar app** at `~/Library/Application Support/ClaudePulse/usage-snapshot.json`. Widgets must not touch keychain or network themselves (sandbox + ACL prompts in the widget process). App pings `WidgetCenter.reloadTimelines` after each fetch. *(Originally App Group container; changed because Xcode 26 requires a provisioning profile for `application-groups` even on macOS, impossible with ad-hoc signing. The sandboxed widget instead carries a `temporary-exception.files.home-relative-path.read-only` entitlement for that directory, resolved against the real home via `getpwuid`.)*
- **Project generation: XcodeGen** (`project.yml`), so the repo stays diffable and CLI-buildable (`xcodegen && xcodebuild`).
- **Signing: ad-hoc / local** — no Apple Developer cert on this machine (verified: `security find-identity` → 0 identities). Acceptable for a personal app.

## Key facts (verified during research)

### Usage endpoint

- `GET https://api.anthropic.com/api/oauth/usage`
- Headers: `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`, and a Claude-Code-like `User-Agent: claude-code/<version>` (without it: aggressive 429s). Poll interval ≥ ~180 s is reportedly safe.
- Response (utilization 0–100, ISO-8601 reset timestamps; model-specific windows may be `null`):

```json
{
  "five_hour":        { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00+00:00" },
  "seven_day":        { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59+00:00" },
  "seven_day_opus":   null,
  "seven_day_sonnet": { "utilization": 1.0,  "resets_at": "2026-04-16T03:00:00+00:00" },
  "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```

- 429 errors come without `Retry-After`. Treat unknown fields leniently (community-observed shape, not official).

### Credentials (this machine, verified 2026-06-11)

- Keychain (login.keychain-db) holds **three** generic-password items, account `psalkowski`:
  - `Claude Code-credentials` (legacy/default entry)
  - `Claude Code-credentials-27385227` (suffixed — one config dir)
  - `Claude Code-credentials-66beff35` (suffixed — other config dir)
- Newer Claude Code versions suffix the service name per `CLAUDE_CONFIG_DIR`; which suffix is which subscription is determined **at runtime from the payload**, not hardcoded.
- Item payload is JSON: `{ "claudeAiOauth": { "accessToken", "refreshToken", "expiresAt" (epoch ms), "scopes", "subscriptionType", ... } }`.
- `~/.claude-team/.credentials.json` contains ONLY `mcpOAuth` (MCP server tokens) — account tokens are keychain-only on macOS. There is **no local file with usage/rate-limit data** in either config dir (verified by grep for `resets_at`).
- First keychain read from our app will trigger one macOS ACL prompt per item → user clicks "Always Allow".

### Plan / seat labels (profile endpoint)

- Labels come from `GET https://api.anthropic.com/api/oauth/profile` (same OAuth Bearer + `anthropic-beta: oauth-2025-04-20` + `claude-code/<ver>` UA as the usage call; needs the `user:profile` scope, which Claude Code tokens carry). Fetched live per token alongside usage — **no local-file reading**.
- Note: the sibling `/api/oauth/claude_cli/profile` from older clients now **404s**; the working path is `/api/oauth/profile`. Verified shape:

```json
{
  "account": { "email": "…", "has_claude_max": true, "has_claude_pro": false },
  "organization": {
    "name": "Softr Platforms GmbH",
    "organization_type": "claude_team",       // or claude_max, claude_pro, claude_enterprise
    "rate_limit_tier": "default_claude_max_5x", // or _20x, default_raven (team top tier)
    "seat_tier": "team_tier_1"                  // OPAQUE — no documented friendly name
  }
}
```

- **Critical fact:** no Anthropic field (local or API) exposes the literal seat name "Standard"/"Premium". `seat_tier` is an undocumented enum (`team_tier_1`); exhaustive search found no public mapping. We therefore **never string-munge `seat_tier`**.
- Label rules (`PlanLabel.swift`):
  - `claude_max` → rate band from `rate_limit_tier` (`Max 20×` / `Max 5×`); detail = email.
  - `claude_pro` → "Pro"; detail = email.
  - `claude_team` / `claude_enterprise` → title = `organization.name`; detail = **derived** seat + rate band, e.g. "Premium seat · Max 5× limits". Per support.claude.com/9266767, Premium = 6.25× Pro (high usage band), Standard = 1.25× Pro (low band); since only the rate band is machine-readable, the high band (`max_5x`/`max_20x`/`raven`) ⇒ Premium, lower ⇒ Standard. This is an *inference from the official multiplier table*, the closest correct answer available, and is documented as derived.
- Expired/unfetchable token → previous label is retained from the last snapshot.

### Account discovery algorithm

1. Enumerate keychain generic-password items whose service starts with `Claude Code-credentials` (`SecItemCopyMatching`, `kSecMatchLimitAll`, then filter on service prefix).
2. Parse each payload's `claudeAiOauth`; skip items without `accessToken`.
3. **Dedupe by `accessToken` value** (legacy + suffixed entries may hold the same account).
4. Label each account: `subscriptionType` containing `max` → "Personal · Max"; `team`/`enterprise` → "Team"; otherwise show raw type + service suffix. If two accounts share a type, disambiguate with the service suffix.
5. `expiresAt` ≤ now → token expired → don't call the API for that account; mark snapshot stale.

### Statusline fallback (post-MVP, not in scope now)

`~/.claude/statusline-command.sh` receives `rate_limits` (`five_hour`/`seven_day`, `used_percentage` 0–100, `resets_at` epoch *seconds*) on stdin while a session runs. It could dump per-subscription JSON for the widget with zero token handling. Deliberately deferred — the OAuth endpoint covers everything while CC is closed, which the statusline cannot.

## Architecture

```
claude-pulse/
├── project.yml                 # XcodeGen
├── ClaudePulse/                # menubar app target (LSUIElement)
│   ├── ClaudePulseApp.swift    # @main, MenuBarExtra(.window)
│   ├── UsagePoller.swift       # 180s timer: discover accounts → fetch → write snapshot → reload widgets
│   ├── MenuBarLabel.swift      # compact label (two colored % values)
│   └── PopoverView.swift       # claude.ai-style panel, both subscriptions
├── ClaudePulseWidget/          # WidgetKit extension target (sandboxed + app group)
│   ├── ClaudePulseWidget.swift # TimelineProvider reading snapshot file
│   └── WidgetViews.swift       # medium (both subs) + small (first sub) families
├── Shared/                     # compiled into both targets
│   ├── Models.swift            # UsageWindow, AccountUsage, UsageSnapshot (Codable)
│   ├── KeychainCredentials.swift
│   ├── UsageClient.swift       # URLSession call to /api/oauth/usage
│   └── SnapshotStore.swift     # read/write JSON in app-group container
└── scripts/probe.sh            # one-shot endpoint verification (prints redacted output)
```

- **Snapshot path:** `~/Library/Application Support/ClaudePulse/usage-snapshot.json` (see design decision above for why not an App Group container).
- **Snapshot format:** `{ fetchedAt, accounts: [{ id, label, subscriptionType, tokenExpired, fetchError?, fiveHour: {utilization, resetsAt}, sevenDay: {...}, sevenDayOpus?, sevenDaySonnet? }] }`.
- The poller fetches all accounts concurrently, writes the snapshot atomically, and reloads widget timelines. Snapshot persists across app restarts (last-known data shown immediately).

## UI

### Menubar label (always visible)

`◔ 28 · ◑ 45` — one circle+number per subscription (P then T), colored green <30 / yellow 30–69 / red ≥70 (matches the user's statusline conventions). Circle glyphs: ○◔◑◕● at 0/13/38/63/88 thresholds. Shows `–` for an account with no data.

### Popover (click)

Per subscription, a card titled "Personal · Max" / "Team":
- **Current session** — progress bar + "X% used", subtitle "Resets in 3 hr 17 min"
- **Weekly · all models** — bar + %, subtitle "Resets Fri 2:00 PM"
- **Weekly · Opus / Sonnet** rows only when the API returns them non-null
- Footer: "Updated 2 min ago" + stale/expired warning when applicable, manual Refresh button, Launch-at-login toggle, Quit.

### Widget

- **systemMedium** (primary): two columns, one per subscription — name, 5h bar + "resets in Xh Ym", weekly bar + "resets Fri 14:00".
- **systemSmall**: single subscription (first one; configurable post-MVP).
- Staleness: when snapshot older than 15 min, show "updated HH:mm" footnote in secondary color.

### Auto-start sessions (added post-MVP)

Shared toggle (gear menu, `UserDefaults` key `autoStartSessions`, default off). After each poll, for every account whose 5-hour window is inactive (`five_hour` null, or `resets_at` in the past, or zero utilization with no reset time) and whose token is fresh, the app POSTs a minimal 1-token Haiku message to `api.anthropic.com/v1/messages` (OAuth bearer + `anthropic-beta: oauth-2025-04-20` + Claude Code UA + the Claude Code system-prompt prefix, which OAuth inference requires). That first message starts a new 5-hour window. 15-minute per-account cooldown prevents retry loops; a successful ping schedules a follow-up usage fetch ~8 s later so the new window shows up immediately. Failures surface as an "Auto-start failed" badge (hover for detail).

## Edge cases / invariants

- Token expired or keychain read denied → card shows last data + explicit stale reason; app never crashes on missing accounts (0, 1, or N accounts all render).
- API 429 → back off (skip next cycle), keep last snapshot.
- `resets_at` in the past → treat window as reset (show 0-ish state hint "resets momentarily" until next fetch).
- Clock display uses local timezone; "resets in" uses relative formatting under 24 h, weekday+time beyond.
- The app must never write to keychain, never call any OAuth token endpoint, never modify Claude Code's files.
- Polling only while menubar app runs; widget shows snapshot age honestly.

## Acceptance criteria

- [ ] Menubar shows both subscriptions' 5-hour utilization at a glance; popover shows session + weekly (+ per-model when present) with reset times for both subscriptions.
- [ ] Widget (medium) shows both subscriptions with 5h + weekly bars and reset times; addable from the widget gallery.
- [ ] Data matches Claude Code's `/usage` output for both accounts.
- [ ] No token refresh calls ever made; Claude Code login unaffected after extended use.
- [ ] App survives: expired token, missing account, no network, 429.
- [ ] Builds from CLI: `xcodegen && xcodebuild -scheme ClaudePulse`.

## Out of scope (MVP)

- Prediction/ETA of limit exhaustion (post-MVP: persist utilization history, linear fit over trailing window).
- Statusline-dump fallback data source.
- Widget configuration intents (choose subscription per widget), notifications at thresholds, extra-usage credits display.
- App Store distribution / notarization.

## Verification

1. `scripts/probe.sh` (run by the user — reads keychain, calls endpoint once per account, prints redacted JSON) — proves endpoint + both accounts before/alongside the build.
2. Build + launch; user grants keychain ACL ("Always Allow") and verifies popover numbers against `/usage` in both subscriptions.
3. Add widget from gallery; verify rendering + refresh after a heavy CC session.
