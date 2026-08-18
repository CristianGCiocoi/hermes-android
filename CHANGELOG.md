# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

## [1.0.26-hermesapk.26] - 2026-08-18

### Fixed

- The inline transcript and the top-right Activity Center now expose distinct
  projections of the same Gateway state instead of duplicating foreground
  tools, delegated tasks, and current-turn status.
- Foreground Reasoning, tools, and delegated work remain collapsed alongside
  the response. The Activity Center is reserved for recovery state, input
  requests, notifications, tool failures, background results, and reviews.
- The Activity badge continues to count only items that need attention; normal
  completed foreground work does not create a badge or duplicate history.

### Validation

- Generic Gateway behavior and the optional interaction-mode capability are
  unchanged from `.25`.
- Flutter analysis passes with zero issues; all 389 Flutter tests pass,
  including the focused Activity projection, scroll, interaction-mode, and
  clarification regressions.

## [1.0.25-hermesapk.25] - 2026-08-18

### Added

- Optional per-chat `Standard`, `Interview`, and `Grill` interaction modes,
  negotiated through an exact versioned Hermes Gateway capability.
- Server-owned one-question-at-a-time Interview and Grill clarification labels,
  including the current question step in the existing clarification dialog.

### Compatibility and safety

- Generic and older Gateways remain fully supported in Standard mode. If the
  capability is absent or malformed, Android sends no `interaction_mode.get`
  or `interaction_mode.set` request.
- Mode changes are session-scoped, revision-bound, refused while a turn is
  active, persisted by Hermes, and accepted by Android only when the RPC receipt
  exactly matches the subsequent `session.info` readback.
- Android does not prefix user messages or simulate Interview/Grill locally.

### Validation

- Flutter static analysis passes with zero issues.
- All 388 Flutter tests pass, including adversarial capability/receipt parsing,
  generic-Gateway zero-mode-RPC compatibility, session readback, and existing
  clarification regressions.

## [1.0.24-hermesapk.24] - 2026-08-18

### Added

- A centralized Hermes Activity Center with explicit lifecycle and dismissible
  review notices, replacing permanent review cards in the transcript.
- Native creation of Hermes Projects from the Projects screen while preserving
  the server-owned `projects.list` / `projects.set_active` authority.
- A per-session permission selector for `Standard` and `Full control`, with
  strict Gateway readback and fail-closed handling of unsupported values.
- A unified per-message action menu for Copy, Select text, Share, Read aloud,
  Edit and resend, and Regenerate response.
- Five application color palettes and an optional high-contrast mode, applied
  consistently to light and dark themes.

### Changed

- Streaming answers remain after Reasoning and Hermes activity, activity cards
  start collapsed, long conversations open at the latest content, and a
  persistent Latest affordance returns to the end without forcing scroll while
  the user is reading earlier messages.
- Standard conversations continue to use the existing individual
  `clarify.request` / `clarify.respond` flow. Interview and Grill are reserved
  for a later versioned Agent/Gateway contract and are not simulated locally.

### Validation

- Flutter static analysis passes with zero issues.
- All 379 Flutter tests pass, including palette persistence, contrast,
  streaming/scroll, Projects, permissions, Activity Center, and message-menu
  regressions.

## [1.0.14-hermesapk.14] - 2026-07-30

### Added

- Remote Gateway attachments now identify the mobile source channel and active
  ATLAS profile so the server can register them in the canonical document inbox.
- The attachment response carries the document-intake status without exposing
  credentials or raw user/session identifiers.

### Changed

- Chat upload remains available if document catalog registration is temporarily
  unavailable and shows a non-blocking pending notice to the operator.

### Validation

- Static analysis passes with `--fatal-infos`.
- 113 Flutter tests pass.
- The synthetic Desktop Gateway contract suite passes with the extended
  `atlas_intake` response.
- An ARM64 debug APK builds successfully. It remains a private test artifact
  signed with the Android debug certificate.

## [1.0.13-hermesapk.13] - 2026-07-30

Community Remote Gateway edition based on Hermes Android 1.0.13.

### Added

- A unified Desktop Gateway JSON-RPC chat transport with session resume/create,
  reconnect handling, streaming, interruption, and persistent chat mapping.
- Per-chat model and thinking-effort selection. Supported effort values follow
  the Hermes Desktop contract: `none`, `minimal`, `low`, `medium`, `high`,
  `xhigh`, `max`, and `ultra`.
- Up to 10 mixed attachments per message, 16 MiB each, uploaded through
  `file.attach`, with per-file progress, remove, failure, and retry states.
- Selectable Markdown, Copy, Read aloud, Edit and resend, Regenerate, Stop,
  conversation export, session search, Rename, Branch, and Delete.
- Native handling for approval, sudo, secret, clarification, notification,
  reasoning, interim message, tool activity, background result, review summary,
  and subagent events from Hermes Desktop Gateway.
- A local synthetic Desktop Gateway fixture and contract test suite under
  `tools/fake_gateway`.
- A separate debug application ID (`com.hermesagent.hermes_android.dev`) so the
  community test build can coexist with the upstream application.

### Changed

- Text, images, and files in Desktop Gateway profiles now share one session and
  one JSON-RPC transport instead of splitting new messages across REST and
  WebSocket paths.
- Model and thinking overrides are scoped to one conversation; the profile
  default remains controlled from Settings.
- Release signing no longer falls back to the Android debug key. A real release
  requires an explicitly configured private keystore.

### Fixed

- Branch actions no longer open a dialog while the popup route is being torn
  down, preventing the Flutter `_dependents.isEmpty` assertion.
- If Hermes creates a branch but returns a late JSON-RPC error, the app refreshes
  history and reconciles the successful result instead of showing a false
  failure.
- Dashboard dialogs no longer refresh their parent while an IME-dependent route
  is closing.
- Microphone permission is requested only after an explicit microphone action.
- Session identity, official terminal events, retry state, delayed events, and
  duplicate tool progress are handled defensively.

### Validation

- 110 Flutter tests pass.
- The synthetic gateway contract suite covers Dashboard authentication,
  session lifecycle, model/reasoning configuration, attachments, streaming,
  interruption, interactive requests, activity, notifications, and subagents.
- The ARM64 debug build was validated on a physical Android phone connected to a
  private Remote Gateway network.

## [1.0.13]

### Changed
- Updated the Flutter package version to `1.0.13+113` so generated Android
  builds report the same version as the GitHub `v1.0.13` release.

## [1.0.12]

### Added
- **Session source filters** in Settings. Mobile users can now choose which
  Hermes session origins appear in the session list, including scheduled tasks,
  developer tool calls, CLI chats, desktop sessions, and messaging platforms.
- Filter preferences are scoped per saved connection so settings for one Hermes
  gateway do not affect another.

### Changed
- Session filtering is performed client-side against each session's recorded
  source, so it works without any Hermes Gateway API changes.

## [1.0.8]

### Added
- **Reverse-proxy path prefixes** for Gateway API and dashboard routes. Gateway
  prefixes are applied before `/api` and `/v1` routes; dashboard prefixes are
  applied before dashboard `/api` routes.
- **Proxied dashboard mode** for deployments where nginx/Caddy/another proxy
  injects dashboard authentication. In this mode the app sends clean dashboard
  requests without scraping the SPA token or using password login.
- **Dashboard / Proxy Settings** can edit gateway prefix, dashboard prefix,
  proxied-dashboard mode, dashboard port, and dashboard credentials after a
  connection is created.

### Fixed
- Existing chat history, streaming chat completions, session browsing, API-key
  validation, and dashboard validation now consistently use configured path
  prefixes.

## [1.0.7]

### Added
- Support for **password-protected dashboards**: the Memory, Cron Jobs, Skills,
  and Settings screens now authenticate against a basic-auth dashboard via the
  `/auth/password-login` flow and reuse the returned session cookie. Open
  (`--insecure`) dashboards continue to work via the existing token scrape.
- **Configurable dashboard port** per connection (`dashboardPortOverride`),
  defaulting to the previous behaviour (`9119` for HTTP, the external port for
  HTTPS) when unset.
- **Dashboard details in the Add Connection dialog** under a collapsible
  "Custom dashboard details" section, plus a **Dashboard Login** entry on each
  connection's overflow menu. Both validate the dashboard before saving.

### Changed
- `DashboardClient` accepts an optional `http.Client` for testability and
  de-duplicates concurrent login / token requests.

### Fixed
- Updating a connection's API key no longer clears its saved dashboard settings.
