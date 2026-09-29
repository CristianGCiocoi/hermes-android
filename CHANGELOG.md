# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

## [1.0.34-hermesapk.34] - 2026-09-29

### Fixed

- Replaced the Android Home-screen Add Connection action with a real native
  `ImageButton` embedded in the Flutter layout. Android accessibility clients
  now receive one stable native resource ID and the exact content description
  `Add Connection`, without depending on Flutter's virtual semantics bridge.
- Routed the native click back to the existing Flutter Add Gateway Connection
  dialog through a value-free per-view method channel. No connection value,
  credential, Gateway behavior, or authority boundary crosses this channel.

### Verification boundary

- Flutter tests still cover the fallback control and dialog contract.
- Release acceptance additionally requires the packaged x86_64 APK to expose
  and activate the native control through Android UIAutomator on the qualified
  AVD. Flutter-only results are not sufficient for this release.

## [1.0.33-hermesapk.33] - 2026-09-28

### Fixed

- Propagated the saved connection's `dashboard_proxied` mode into the Desktop
  Gateway authentication client. Proxied connections now request the
  WebSocket ticket directly instead of incorrectly scraping the Dashboard SPA
  for a session token.
- Restored authenticated session initialization and retained Notification
  reconciliation for proxy-terminated Remote Gateway deployments that do not
  store a local Dashboard username/password.

### Compatibility and authority

- Password-authenticated and insecure/open Dashboard modes retain their
  existing behavior.
- Generic Gateways still receive zero Notification RPCs when the exact
  capability is absent.
- Android remains a presentation and factual-delivery client; server-side
  Notification semantics and lifecycle authority are unchanged.

### Verification

- Added an adversarial proxy-topology regression that rejects every fallback
  authentication request and requires the exact `ws-ticket → session.resume →
  notification.pull` path without Cookie or SPA token headers.

## [1.0.32-hermesapk.32] - 2026-09-28

### Fixed

- Notification delivery now reconciles independently from optional
  Standard/Interview/Grill state. A failed interaction-mode read no longer
  prevents an advertised `notification.pull`.
- Pending notifications are checked again on later app resumes. Only
  simultaneous pulls are coalesced; a failed or empty pull is no longer cached
  for the lifetime of the authenticated socket.
- Concurrent Desktop connection/session initialization is serialized so one
  chat cannot race itself into multiple sockets or duplicate session opens.
- Duplicate `notification.show` events for the same notification revision are
  coalesced locally. Android keeps the deterministic native result reference
  and reports only the factual delivery outcome.

### Compatibility and safety

- Generic and older Gateways remain unchanged: no notification RPC is sent
  unless the exact `hermes.notification.delivery.v1` capability is advertised.
- Pull acknowledgements are now strict and fail closed when malformed. Android
  remains a presentation and delivery-result adapter; it does not own or infer
  semantic Notification lifecycle state.
- The flow reuses the existing authenticated Desktop connection/session and
  does not submit a prompt, start an agent, select a model, or invoke a model.

## [1.0.31-hermesapk.31] - 2026-09-27

### Fixed

- Advanced connection settings now open in a dedicated value-free native
  dialog with Proxy, Dashboard, and Desktop panels. Controls no longer depend
  on being below the clipped portion of the Add Connection form.
- Stable Android identifiers cover the Advanced dialog, every panel selector,
  Done, Dashboard prefix/port/username/password, and Desktop Gateway URL.
  Dashboard and Desktop controls are visible in the native accessibility tree
  when their panel is selected.

### Compatibility and safety

- Existing field identifiers and stored connection data remain unchanged.
  Generic Gateway behavior, optional ATLAS enrichment, dashboard validation,
  Desktop Gateway routing, secure credential storage, and offline startup are
  unchanged.
- API keys and Dashboard passwords remain obscured. No field value, secret,
  host, route, prompt, or message content is used in a native identifier.

### Validation

- Widget coverage navigates the exact Add Connection → Advanced → Dashboard /
  Desktop → Done → Connect path and verifies unique actionable identifiers and
  secret masking before native Android qualification.

## [1.0.30-hermesapk.30] - 2026-09-26

### Fixed

- The Flutter semantics tree now remains published for the lifetime of the
  application. Native Android selectors can therefore resolve the `.29`
  value-free identifiers immediately, even when an automation client queries
  `resource-id` without first requesting a hierarchy dump.
- The identified Add Connection, Advanced, Cancel, Connect, saved connection,
  and New Chat nodes now expose their tap action directly. Native automation
  can activate the same controls it resolves, without falling back to visible
  labels or screen coordinates.
- The lifetime handle is released with the root application state. Existing
  platform accessibility activation continues to coexist with it.

### Compatibility and validation

- Identifier strings and their privacy boundary are unchanged from `.29`.
  Generic Gateway behavior, offline startup, package/signing lineage, and all
  existing application features remain unchanged.
- Qualification uses direct UiAutomator2 `resourceId` selectors before any
  hierarchy dump, matching the client behavior that exposed the `.29` gap.

## [1.0.29-hermesapk.29] - 2026-09-23

### Added

- Stable, unique Android accessibility identifiers now cover Add Connection,
  the add/edit dialog, every connection field and switch, Cancel, Connect,
  each saved connection, New Chat, and the empty chat composer.
- Saved-connection identifiers use only the opaque connection ID. Connection
  labels, hosts, usernames, API keys, and passwords never become part of an
  automation identifier.

### Safety and validation

- API key and Dashboard password fields explicitly remain obscured in the
  accessibility tree. Existing secure-storage tests continue to prove that
  credentials do not enter the non-secret connection metadata store.
- Widget qualification covers a clean cold start, the complete expanded form,
  unique identifiers, secret-field masking, saved connections, New Chat, and
  the empty composer. The consumed ATLAS product-E2E attempt was not retried.
- Generic Hermes Gateway behavior and all `.28` offline-start guarantees remain
  unchanged.

## [1.0.28-hermesapk.28] - 2026-09-22

### Fixed

- Application startup and every Hermes wordmark now use Android's packaged
  system serif family. First paint no longer imports or invokes `google_fonts`,
  fetches Cinzel from an external host, or depends on Internet font delivery.
- A failed or unavailable external font service can no longer leave a normal
  cold launch on the splash screen.

### Compatibility and validation

- The `.27` generic `hermes.notification.delivery.v1` contract and all existing
  Gateway behavior remain unchanged.
- Static and widget regressions enforce a network-free wordmark, dependency
  removal, and successful local rendering before APK and cold-start
  qualification.

## [1.0.27-hermesapk.27] - 2026-09-22

### Added

- Configurable Desktop Gateway connections can now negotiate the optional,
  Hermes-owned `hermes.notification.delivery.v1` capability.
- A capable Gateway may expose one pending item through `notification.pull`;
  Android presents its bounded `notification.show` projection through the
  normal OS notification channel and returns the native factual outcome through
  `notification.delivery_result`.
- Android 13+ requests `POST_NOTIFICATIONS` through the standard runtime flow.
  Permission denial is preserved as a factual result instead of being reported
  as a successful delivery.

### Compatibility and safety

- Older and generic Gateways receive zero notification RPCs. Existing chat,
  session create/resume, Projects, attachments, and interaction modes remain
  unchanged.
- The notification bridge receives only presentation metadata. API keys,
  Dashboard credentials, connection routes, and server authority are never
  passed to Android's platform notification channel.
- The product build contains no CS-141 compile-time gate, hard-coded private
  route, internal CA, canary provisioning, SecretRef relay, or ATLAS
  Notification authority.

### Validation

- Focused contract, native-bridge, capability, pull-once, callback, generic
  compatibility, connection persistence, and release identity tests are part
  of the release qualification suite.

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
