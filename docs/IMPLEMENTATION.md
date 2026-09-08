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

## Native reference inspection and utility layout

Inspected window captures from the installed Raycast launcher, LookAway Now window, and Session main interface. Raycast uses neutral translucent surfaces, bright primary text, low-emphasis controls, and an action footer. LookAway centers its current state in a compact 420-point window. Session separates setup from history, but its permanent sidebar was deliberately not adopted. macOS reported Accessibility automation disabled, so exhaustive settings-tab and menu-bar inspection was blocked; these captures are not a full application audit and remain local, untracked research files.

The current UI supersedes the navigation rail and mint theme above: a 620×450 workspace with bottom navigation, no Focus heading row, a typographic timer, neutral actions, and on-demand full-width notes. Notes presentation survives destination changes, and timer actions remain available while writing. Reminders use a full-width list and an on-demand editor; settings use five compact horizontal tabs. Destructive cycle actions are under an ellipsis menu with confirmation. Native window controls are retained without a title heading. Independent code and screenshot reviews informed the corrections.

The portrait refinement constrains the window via SwiftUI content-size resizability rather than only changing its default size, preventing restoration of the old oversized layout. Focus and Reminders use 420×520; notes remain visible under the centered timer. Reflection temporarily adds height while reducing the countdown type size; Stats (formerly History) gets enough width for calendar and timeline. Settings uses 560×450. Enabled switches are blue, icon-only menus hide redundant indicators, and the add action is named New Reminder. No stored timer or session schema changes were needed.

Cursor-warning movement now uses AppKit's window-associated CADisplayLink in common run-loop modes instead of the 250ms reminder tick. It samples cursor location at display refresh, keeps a stable hosting view, and updates text only on visible-second or pause-state changes. The warning is clear, click-through emoji/text with glyph shadows rather than a glass box. Position clamps at display edges instead of abruptly switching sides. The weak display-link target and explicit invalidation avoid retained controllers and work after dismissal. The existing ten-second idle countdown remains unchanged. This is an Apple API-based implementation, not a claim about LookAway's private internals.

The completion-step refinement supersedes automatic focus-to-break transitions: completed focus now stages a ready break and displays dedicated emoji feedback instead of the timer/notes view. Continue or Enter starts the break exactly once. Break-to-focus remains automatic. Pending feedback is restored only for a ready break paired with the latest completed focus, including when a rating was saved before quit; older unanswered sessions cannot appear during active focus. Direct stop controls replace the timer's actions menu. Explicit Abandon at a deadline still stops the cycle, preserving the completed record without starting any phase.

## Release boundary

The source and local app are implemented. Production distribution is a separate credentialed step: this machine has no Developer ID Application signing identity, and no notarization profile or production update feed/key was supplied. Therefore the local app truthfully disables unconfigured updates. The guarded release script prepares notarized, Sparkle-signed artifacts once those external requirements exist; it does not invent credentials or silently publish an ad-hoc release.

## Notch and completion prompts (September 2026)

Studied [NotchNest's official feature descriptions, FAQ and interactive demo](https://notchnest.app/), including its expanded screen-edge dashboard. Adopted top-edge anchoring, rounded lower corners, hover expansion and a notchless fallback. Kept only Interval's timer, checklist, reminders and reflection rather than copying its music, clipboard, camera or launcher modules. The user's LookAway reference informed the separate rounded completion prompt and pill actions; it does not justify changing Interval's completed-session records or adding pause controls.

AppKit's [safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) and [auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc) provide hardware-cutout geometry in global screen coordinates. [NSTrackingArea](https://developer.apple.com/documentation/appkit/nstrackingarea) supplies hover entry/exit without mouse polling. A nonactivating panel expands without taking keyboard focus; click opts into editing. Collapse is delayed 450ms, protected while editing, and available explicitly or with Escape. Reduce Motion removes frame animation. The panel targets a notched display when present, otherwise the primary display; display changes recalculate geometry.

Settings → General → Quick access exposes Notch panel (opt-in to avoid conflicting utilities) and Session-end popup (on by default). The completion popup offers Later or Reflect; Reflect expands in place to the shared feedback form. Later suppresses repeated prompts for that completion during this app run, while feedback remains available in the app/menu/notch. A pending completion can prompt again after relaunch. The existing Continue-to-start-break rule is unchanged. Both native surfaces hide during session unavailability and reminder overlays, reuse the saved appearance, and never activate the app merely by appearing. System notifications remain supported independently.

## State-sensitive product and design audit — current behavior

This section supersedes the historical workflow descriptions above. Independent product-manager and macOS-designer reviews covered each source-defined screen and state: focus ready/running/ending, break running/overtime, reflection, menu and notch pages, reminder warning/suppression/takeover/preview, reminder CRUD, Stats and filters, and all five Settings tabs. A second independent pass reviewed the implemented changes and fresh light/dark native captures.

- Focus completion starts the appropriate break immediately during normal operation. Rating and thoughts are optional and never reset its deadline. Inactivity recovery does not replay missed phases. Break completion waits for explicit Resume focus; there are no user-facing pause controls.
- Reflection promotes Continue break while a break runs, Start break after inactive recovery, and Resume focus after a break ends. The compact notch keeps ratings, live time, and action visible without scrolling or increasing its height; the main window and menu retain journal editing.
- Stats and Reminders retain the actual live timer and resume action even with unanswered reflection. Reflection is a secondary icon action. Breaks no longer expose editable focus title/category controls. Break records have no focus-rating form; unrated focus records say Not rated.
- Reminder previews are explicitly labeled Preview and close immediately with their button or one Escape. They do not modify recurrence. Real takeovers retain the five-second skip gate and double-Escape gesture. Long messages scroll independently of the title, counter, and actions.
- Empty reminder lists offer New reminder and customizable templates. Reminder fields have persistent labels and constrained width. Sound preview is absent for None. Empty Stats replaces redundant empty breakdowns with one explanation.
- Heads-up headings describe the impending event; adjustment buttons describe the action. Settings copy distinguishes the one-minute notification toggle from automatic overdue-break reminders. Updates displays the installed version and remains disabled without a configured signed feed.

Reviewer suggestions conflicting with explicit product choices were rejected: retain Others, Extend, secondary Take break icons, the persistent blank checklist row, and optional journal copy without extra labels. A proposed timeline/footer overlap was checked against the native scroll layout rather than treating a clipped scroll viewport as an unreachable control.

Review limits: captures and automated native UI checks do not establish real Calendar authorization, browser-microphone detection, physical multi-display behavior, VoiceOver completeness, or the subjective quality of audible playback. These remain explicit acceptance checks, not implied passes.

## System accent and two-pane dashboard

The dial and shared controls now use the system accent. Native macOS 26 interactive Liquid Glass is shared across icon, selection, and primary buttons, with opaque accessibility fallbacks. Break actions use a neutral rest symbol; the main break view gives the countdown prominence without a clock dial. Text actions use Title Case.

The right sidebar pages horizontally between Overview and Calendar, with persistent bottom navigation. Overview keeps the resizable checklist, reminders, and upcoming timed events today; Calendar reuses DayTimeline. Calendar access has a Settings action rather than an unexplained empty pane. Persisted legacy phase colors remain readable but are no longer exposed as competing theme controls.

Native UI coverage verifies second-page positioning and returning to Overview; event coverage excludes ended/all-day events and protects today's events from Stats date navigation.

## Short overlays and per-display wallpaper

Reminders support Full Screen (minimum five seconds) and Overlay (minimum one second). Overlay is a centered, click-through, nonactivating panel on the cursor's display; it leaves the workspace visible and closes automatically. The Blink template defaults to three seconds every five minutes and permits focus-time delivery while retaining calendar/microphone suppression. Existing reminders are unchanged.

Fullscreen wallpaper uses ScreenCaptureKit to capture only the matching display's desktop backdrop window: WallpaperAgent or Dock's below-desktop wallpaper layer. This avoids NSWorkspace's stale DefaultDesktop.heic path on modern macOS. Captures are one-shot, canceled on closure, and never include application windows. Screen Recording access is required for the rendered wallpaper; an explicit editor action opens that permission setting. Without permission or when capture fails, the static wallpaper API remains the fallback.

Validation: 166 tests passed, including short-duration persistence/expiry, click-through nonactivation, and strict wallpaper-window/display matching. Wallpaper-only captures on both connected displays and the fullscreen, overlay, and display editor renders were inspected.
