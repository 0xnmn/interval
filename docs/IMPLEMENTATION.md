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

## Visual redesign — reference study and review

The initial generic native layout was rejected. The redesign studied actual product screens and motion, not only marketing copy:

- Session's [desktop screenshot](https://www.stayinsession.com/xdr.jpg), [multi-device hero](https://www.stayinsession.com/hero.png), and [review screen](https://www.stayinsession.com/ipad-review.png): a dominant circular timer, separate work history, month/day navigation, and reflections tied to sessions. Adopted timer hierarchy and separated notes/history, not Session's red palette, task taxonomy, or italic typography.
- Raycast's [Notes](https://www.raycast.com/_next/static/immutable/media/raycast-notes.0khgr6jj73_r6.png), [Focus](https://www.raycast.com/_next/static/immutable/media/focus.1ii6df8wrisc6.png), and [Schedule](https://www.raycast.com/_next/static/immutable/media/schedule.1_cr_7zp48ify.png) screens: smoked charcoal, fine rims, off-white type, restrained selection fills, and compact action groups. Adopted these surface principles with an Interval-specific mint accent; avoided the decorative marketing backdrops.
- LookAway's [break sequence](https://lookaway.com/videos/hero-video-converted.mp4), [posture animation](https://lookaway.com/videos/posture-website-v2.mp4), and [settings screen](https://lookaway.com/images/v2/screenshots/3.jpg): quiet contextual warnings, centered restorative messages, discoverable postponement, and grouped configuration. Preserved Interval's customizable reminder semantics rather than copying LookAway's enforcement model.

Implementation separates semantic styling in `Theme.swift` from existing state/engine contracts. Native behind-window `NSVisualEffectView` supplies glass; Reduce Transparency gets an opaque surface. Timer animation honors Reduce Motion. The main workspace uses a narrow navigation rail, hideable persistent notes, explicit completion reflection, and a calendar/day-detail history. Settings use stable navigation with grouped native controls; reminders have a selectable list, design preview, and scrollable advanced controls.

An independent plan critique preceded implementation. Separate implementation agents owned reminder, settings, and workspace presentation. Adversarial code and rendered design reviews caught minimum-height regression, motion preference handling, transient settings message loss, unreliable native split-view rendering, and low-contrast buttons. Corrections restored the 940×540 minimum, preserved General settings messages across navigation, replaced problematic splits, and provided a consistently legible primary action style. Expanded reminder scrolling was exercised in a normal-height native viewport, not hidden by an oversized screenshot.

## Minimal workspace and automatic cycle

The subsequent simplification removes manual timer-kind selection: one Start authorizes an automatic focus → break → focus loop. Only completed focus sessions advance long-break cadence. Each next phase begins at the observed completion time; the app never synthesizes catch-up records. Pause at a deadline produces a paused next phase; Abandon at a deadline preserves the completed record but stops the cycle. Reflection and notes never gate progression.

Lifecycle handling now pauses both focus and breaks on sleep, lock, screensaver, user switching, or quit; both phase types checkpoint for paused crash recovery. Resume is explicit after returning. This supersedes the initial break-deadline continuation behavior above.

All surfaces were simplified: darker smoked background, narrow navigation, no timer mode tabs or enclosing cards, plain persistent notes, concise reflection, calendar beside the day timeline, compact reminder editor, flat settings rows, and a smaller menu and cursor warning. Essential permissions and errors remain. Independent plan, adversarial code, and rendered design reviews accompanied the work; targeted tests cover automatic cadence, deadline actions, lifecycle pauses, late observations, and reflection during running breaks.

## Release boundary

The source and local app are implemented. Production distribution is a separate credentialed step: this machine has no Developer ID Application signing identity, and no notarization profile or production update feed/key was supplied. Therefore the local app truthfully disables unconfigured updates. The guarded release script prepares notarized, Sparkle-signed artifacts once those external requirements exist; it does not invent credentials or silently publish an ad-hoc release.
