# Interval

A native macOS focus timer and considerate healthy-break companion. Built with SwiftUI, AppKit, EventKit, AVFoundation, UserNotifications, and Sparkle. No web runtime, account, telemetry, or cloud sync.

## Build and run

Requires **macOS 26 or newer**, Xcode 26 with its command-line tools selected, and network access for the initial pinned Sparkle dependency download.

```sh
swift test
./scripts/build.sh
open .build/Interval.app
```

Open `Package.swift` in Xcode to work on the sources. Use the build script to run a complete `.app`: it creates the Info.plist, icon, embedded updater framework, and local ad-hoc signature. `swift run` is not a substitute for the bundle when testing macOS permissions and notifications.

The default build targets the build Mac's architecture. It is a local development build, **not a notarized public release**. See [release instructions](docs/RELEASING.md) for Developer ID signing, notarization, and automatic-update distribution.

## Use Interval

- **Focus cycle:** 25-minute focus sessions alternate with 5-minute breaks, with a 10-minute long break after every four completed focus sessions. All four values are configurable. Focus completion waits for feedback; Continue starts the break. Natural break completion automatically starts focus while the app is active. There is no pause or resume. Break ends unfinished focus with confirmation; Abandon stops the interval; End Break finishes a break early and leaves focus ready to start.
- **Time controls:** the running timer shows its start and end time. Click ± to add/remove five minutes from this interval only; hover or right-click for 5-, 10-, and 15-minute choices. Remaining time is limited to one minute–three hours.
- **Appearance:** timer actions use icons with hover hints: play to start, coffee to break, briefcase to end a break, and stop to abandon. Focus defaults to green and breaks to blue; choose their colors in Settings → Timer. General controls follow the macOS accent color. Upcoming reminders show a live minutes-and-seconds countdown unless suppressed.
- **Reflect:** completed focus sessions are saved immediately. A dedicated completion screen offers Distracted, Neutral, or Focused emoji choices and a multiline thought field. Press Continue or ⌘Return to start the break; Return inserts a new line. Edit reflections later in Stats. Old unanswered feedback never interrupts a new focus session.
- **To-dos:** one persistent checklist across every session, alongside today's stats and calendar. Return inserts the next row, ↑/↓ navigate, and Backspace removes an empty row while keeping at least one editable item. Check off items or delete them from their context menu; the menu bar also adds to-dos. Existing scratchpad lines migrate to unchecked items. Session reflections remain separate.
- **Session identity:** edit the title above the dial and choose a category. Both carry into subsequent intervals. Manage Categories creates, renames, and deletes categories; saved logs preserve their original names.
- **Timeline and Stats:** the dashboard combines today's saved sessions and Apple Calendar events chronologically. Stats shows one selected day: navigate the week strip or use the date picker for any date. Category bars show focus-time distribution; feedback counts distinguish Focused, Neutral, Distracted, and Unrated. Category filters apply to that day's focus totals and logs, never to calendar events. Breaks are excluded from focus totals and feedback. A persistent live timer bar remains on Stats and Reminders, independent of the date being viewed, with start/break/abandon and reflection actions.
- **Sound:** Silence, Brown Noise, Rain, or Ocean, generated locally with separate focus/break choices and volume.
- **Calendar:** opt in under Settings → Calendar and choose calendars. Interval never creates, edits, or deletes events. macOS calls the required reading permission “Full Access.”
- **Reminders:** use the + menu for a New Reminder or a template: Look Away (20 seconds / 10 minutes), Posture (10 seconds / 20 minutes), Stretch (60 seconds / 30 minutes), or Water (60 seconds / 60 minutes). Templates create normal editable reminders. The list stays visible beside the editor in the main window. Interval presets offer 10, 20, 30, and 60 minutes alongside custom adjustment; none are enabled without being added.
- **Customize:** message, emoji and size, interval, display duration, floating/full-screen presentation, and independent suppression during focus or selected calendar events. Preview does not alter the schedule.
- **Considerate interruptions:** a cursor-adjacent warning counts down ten seconds of idle time. Typing, moving, dragging, and scrolling pause it. Postpone or skip through the menu bar; takeover panels also offer dismissal and postponement. Escape dismisses a takeover. The warning itself is click-through.
- **Settings:** a native sidebar groups Timer, Sound, Calendar, General, and Updates; use arrow keys when the sidebar is focused. Includes launch at login, notification permission, local JSON export, and update preferences. Automatic checks/downloads require a configured signed distribution; local builds explain why updates are unavailable.

### Deliberate behavior

- Closing the window leaves the timer and reminders in the menu bar. Quit explicitly to exit.
- Running intervals retain their deadline through sleep, screen lock, screensaver, user switching, and quit. On recovery, an expired interval is recorded once; missed phases are never replayed. Focus still requires reflection before a break. A break that expires while unavailable leaves focus ready. Legacy paused intervals are preserved as abandoned history rather than resumed.
- Only completed focus sessions advance the long-break cadence. Abandoned intervals remain in History but do not advance it.
- Settings changes affect the next timer, not a running timer.
- Calendar suppression covers overlapping selected-calendar events, including all-day events, except canceled/declined events. Denied/disabled Calendar access cannot provide suppression.
- Missed reminders are skipped while the session is unavailable and on relaunch; there is no replay of every missed recurrence. Visible reminders are serialized. Postponement affects only the current occurrence, not the saved interval.
- Full-screen reminders use ordinary, dismissible floating app panels, not a system lock screen. They respect display work areas and do not disable app switching.

## Keyboard and accessibility

- `⌘⇧S`: start a ready session; disabled during an active interval or pending reflection.
- `⌘1`, `⌘2`, `⌘3`: Focus, Stats, Reminders.
- `⌘,`: Settings. `⌘Q`: Quit.
- Native controls, text editing, semantic materials, descriptive accessibility labels, and selected-state semantics. Motion is restrained; there are no flashing reminders.

## Data and privacy

Local state lives at `~/Library/Application Support/Interval/data-v1.json`. Writes are atomic; an unreadable or unsupported file is not silently replaced. A visible read-only warning protects the original. Export local data from Settings → General. Calendar event content is held in memory and excluded from exports.

Early-development ISO-date files are read with a preserved `data-v1.json.pre-migration` backup. Sessions without recorded pause-aware durations are clearly marked as estimates when necessary.

Activity detection reads system idle durations and pointer position, not key contents. It uses no key logger or global event tap. Cloud synchronization is intentionally not implemented; settings are plain versioned Codable values rather than tied to a cloud provider.

## Source layout

- `Sources/IntervalCore`: persisted value models, pure timer/reminder state machines, calendar date helpers, and JSON storage.
- `Sources/Interval`: app state orchestration, SwiftUI views, and native notification/audio/calendar/reminder/updater adapters.
- `Tests/IntervalCoreTests`: deterministic time, recurrence, date-boundary, and persistence tests.
- `Tests/IntervalAppTests`: real AppStore workflow tests using isolated storage and disabled external services.
- `scripts/build.sh`: reproducible local app packaging and nested signing.
- `scripts/release.sh`: guarded production release preparation; does not upload artifacts.

See [implementation decisions and review record](docs/IMPLEMENTATION.md) and [verification notes](docs/VERIFICATION.md).

## Native visual fixtures

```sh
.build/Interval.app/Contents/MacOS/Interval \
  --snapshot .build/focus.png --snapshot-scene focus
```

Other scenes include `dashboard-running`, `dashboard-break`, `time-options`, `time-options-minus`, `reflection`, `history`, `history-disabled`, `history-no-selection`, `reminders`, `reminder-editor-expanded`, `reminder-countdown-paused`, `reminder-floating`, `reminder-fullscreen`, `menu`, `settings`, `sound-settings`, `calendar-settings`, `general-settings`, and `updates-settings`.

Fixtures use ephemeral local data, no permission prompts, and no active updater/timer/reminder services. They render the actual native views. AppKit off-screen caching does not fully capture every composited sidebar/glass layer; these captures are not a replacement for testing on-screen multi-display behavior.
