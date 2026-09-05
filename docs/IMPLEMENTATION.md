# Implementation decisions and phased review record

## Product and stack

Interval is a macOS 26 native app with a persistent main window, a compact menu-bar window, and transient reminder panels. Focus, History, and Reminders are separate destinations; permanent configuration lives in the standard Settings scene. The scratchpad is global and journals belong to session records.

Use Apple's frameworks where they own the integration: SwiftUI for views and native materials; AppKit for window lifecycle, display placement, export, and the menu; EventKit for calendar reading; AVFoundation for generated ambience; UserNotifications for completion alerts; ServiceManagement for explicit launch-at-login registration. Sparkle 2.9.6 is the only external dependency, pinned for reproducible builds.

Versioned Codable data and atomic JSON storage keep this initial local-only app simple. Plain settings values leave future synchronization possible without building accounts, conflict resolution, or cloud APIs now. Timer and reminder engines are pure value transformations with supplied time/environment, while AppStore owns side effects and persistence.

## Research inputs

- [Apple design guidance](https://developer.apple.com/design/)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [EventKit calendar access](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
- [Sparkle setup and signing](https://sparkle-project.org/documentation/)
- [Session](https://www.stayinsession.com/) informed reflection/history requirements, not copied screen layouts.
- LookAway's considerate interruption model informed inactivity handling; Interval uses its own configurable reminder workflow and native presentations.

## Phase 1 — timer foundation

Implemented timer controls, cadence, menu-bar synchronization, persistence, scratchpad, sleep/recovery semantics, native Settings, and app packaging.

Independent adversarial and design reviews identified paused-timer replacement, destructive load-error fallback, stale action timestamps, imprecise date serialization, missing abandonment confirmation, and misleading save status. Fixed those before proceeding. Added native fixture rendering when macOS denied desktop capture.

## Phase 2 — reflection, history, audio, alerts

Implemented nonblocking feedback/journals, month/day history, generated ambience, notifications, and quick-note append.

Independent reviews identified journal edits clearing feedback, immediate feedback dismissal, stale calendar selection, completion-notification cancellation races, and incomplete quit/recovery service handling. Reflection now binds to saved session data, ends independently of the timer, and keeps explicit Done/Later actions. Completion does not cancel the already-scheduled alert. Active focus checkpoints and intentional quit/sleep handling preserve progress.

## Phase 3 — Apple Calendar

Implemented explicit full-access authorization, user-selected calendars, read-only history events, and an independently refreshed current-day suppression cache.

Reviews found stale permission/cache risks, fixture filtering defects, misleading permission wording, and collapsed history rows. Fixed permission refresh, half-open midnight boundaries, selected-calendar fixture filtering, event/session distinction, day markers, and list layout. No calendar event content is persisted.

## Phase 4 — reminders

Implemented editable templates/custom reminders, recurrence, warning/idle counting, suppression, one-occurrence postponement, previews, cursor positioning, and floating/full-screen panels.

Reviews found stale recurrence replay, blocked-loop idle overcounting, wake/lock assumptions, unrelated CRUD canceling visible reminders, preview schedule mutation, inaccessible labels, and display geometry defects. Fixed startup coalescing, verified idle accounting, separate session state flags, identity-scoped cancellation, preview isolation, explicit template creation, warning pause copy, click-through warnings, and visible-frame panel placement. Postponing a future reminder only moves it later.

## Phase 5 — release hardening

Implemented Sparkle, deferred installation during active work, login registration, local export, app commands, shared navigation, native icon packaging, and additional workflow tests.

Independent reviews caught Bash 3.2 signing-array failure, incorrect Developer ID timestamp settings, uncompleted deferred-install callbacks, navigation resets, incorrect snapshot dimensions, and insufficient bundled-signature checks. Fixed them and verified the local bundle with deep strict signature verification. Added AppStore tests beyond pure-core coverage, including corruption protection, four-completion cadence, preview isolation, calendar selection, export, and navigation reconstruction.

## Release boundary

The source and local app are implemented. Production distribution is a separate credentialed step: this machine has no Developer ID Application signing identity, and no notarization profile or production update feed/key was supplied. Therefore the local app truthfully disables unconfigured updates. The guarded release script prepares notarized, Sparkle-signed artifacts once those external requirements exist; it does not invent credentials or silently publish an ad-hoc release.
