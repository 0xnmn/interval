# Product review disposition

This pass consolidates the independent product-management, marketing/copy,
user-research, and interface-design audits. Duplicate findings are grouped below;
priority is not a reason to leave an accepted finding unresolved. These are agent
reviews, not interviews with real users or a claim of exhaustive accessibility certification.

## P0–P1: correctness and state clarity

- **Reflection versus break:** the break starts at focus completion. Feedback and
  thoughts save independently. Continue break closes reflection without resetting
  time; Resume focus ends an overdue break. Time adjustment now works while
  reflection remains open. Tests exercise these transitions and persistence.
- **Destructive actions:** inactive Abandon is removed. Running focus/break have
  state-specific confirmation titles. Keyboard actions use confirmation too.
- **Ready timers:** show Duration rather than invented start/end timestamps.
  A recovered ready break has Start break, not an ambiguous coffee-only action.
- **Settings navigation:** restore native selection and arrow navigation. Calendar
  settings links route to Calendar even when Settings is already open.
- **Reminder safety:** microphone, timed-event suppression, all-day exclusion,
  idle handling, skip gating, and immediate preview dismissal remain covered by
  existing workflow tests. Copy no longer promises a queued reminder “after event”
  when the engine skips suppressed occurrences.
- **Long full-screen content:** bound the message viewport, preserve scrolling,
  keep countdown/actions separate, and put overflow guidance outside the text.

## P2: consistency, accessibility, and discoverability

- **Selection and hover:** shared selection style for navigation, date selection,
  reflection ratings, reminder rows/templates, and notch tabs. Selected state has
  an outline and accessibility trait, not just a change of hue.
- **Color:** decorative phase fills remain configurable. Text/icon phase colors
  are separately contrast-adjusted against the app surface: 4.5:1 normally and
  7:1 in Increased Contrast. All seven hues have numerical tests in both themes.
  Increased Contrast uses opaque glass and stronger separators/control outlines.
  Translucent desktop compositing is not covered by those numerical ratios.
- **Keyboard:** app commands expose Start/Resume, Take a break, Abandon, time
  adjustments, navigation, and Open notch panel. Keyboard-opened notch holds its
  heads-up and focus until Escape, then restores the previous key window. The
  shortcut is app-scoped, not a system-global hotkey.
- **Permissions:** Calendar explains read-only usage despite macOS Full Access
  wording. Errors have retry routes. Notifications errors stay in Sound rather
  than appearing on unrelated Settings pages.
- **Reminder naming:** New reminder fallback for blank titles; validation while
  editing; stable accessible toggle names with independent On/Off state.
- **Timeline:** an explicit Now marker distinguishes current time from session
  color. Empty days explain their state; redundant zero-completed text is removed.
- **Motion/sound:** retained one-shot staged entrances, reduced-motion bypass,
  hover feedback, and existing playback tests. Countdown updates do not restart
  entrance animations. No continuous animation or additional polling loop added.

## P3: copy and visual polish

- Sentence-case actions and headings; state-specific abandon wording.
- Consistent section heading hierarchy in Stats and Reminders.
- No duplicate empty-reminder instructions in wide layout.
- Explicit export contents and calendar-event exclusion.
- Singular “Every session” cadence rather than “Every 1 sessions”.
- Updates explain missing configuration without disabled switches or promising
  a downloadable release that has not been published.
- Reflection's help and accessibility hint explain automatic saving and optionality
  without adding another visible label.
- Stable to-do checkbox names; blank row is announced as Untitled to-do.
- Reminder extensions say Extend consistently; countdown says sec.

## Findings examined but not adopted

- **Ban future Stats dates:** rejected. Arbitrary date navigation and upcoming
  calendar events are requested behavior. Today is disabled only when already selected.
- **Replace Others / Category / Continue break:** rejected. These terms reflect
  explicit product decisions; changing them would undo requested behavior.
- **Use 44-point targets everywhere:** rejected as a blanket mobile rule. Native
  desktop controls remain compact (32–36 points), with labels/help and keyboard access.
- **Add permanent optional labels or onboarding paragraphs:** rejected. Use concise
  help and accessibility hints instead of cluttering the focus surface.
- **Say “Waiting for call to end”:** rejected. An active microphone does not prove
  a call. The accurate label is Microphone in use.
- **Duplicate warning emoji:** not reproduced; the warning renders one emoji.
- **Compact content is necessarily inaccessible:** not accepted without evidence.
  Native scroll tests reach the final content on Stats, editor, and long reminders.
- **Hide reflection entirely during break:** rejected. Reflection is optional and
  editable during the automatically running break, not a prerequisite for it.

## Second independent visual review

Four independent reviewers inspected 38 light/dark native captures, divided into
product states, Settings/design, Stats/reminders/user research, and quick-surface
copy; the parent inspected the long-message captures separately. No P0/P1 finding
was reported by those reviewers. The following lower-priority findings were
processed rather than discarded:

- **P2 Settings sidebar fading:** explicitly use primary text even when the page
  has no interactive content. Removed the redundant selection checkmark; native
  row selection remains.
- **P2 Settings content below fold:** use a persistent native scroll gutter
  instead of introducing permanent instructional text. A flash alone was not
  sufficiently discoverable in the follow-up capture.
- **P2 notch contrast:** heads-up countdown and status now use primary text.
- **Primary action follow-up:** Start session uses the same system-accent primary
  style as Resume, avoiding white small text on a bright configurable green fill.
- **P2 ambiguous abandon icon:** already has a state-specific tooltip/accessibility
  label and a confirmation dialog; kept secondary as explicitly requested.
- **P2 reflection save uncertainty:** automatic-save help and accessibility hint
  already present; rejected another persistent Save label/button.
- **P3 completed to-do contrast:** use primary native text; checkbox and strike-through
  communicate completion without dimming readable task content.
- **P3 quick-surface secondary contrast:** increase upcoming countdown and reflection
  break-status contrast.
- **P3 repetitive update heading:** use Software update beneath the page title.
- **P3 humanized reminder durations:** retained live second precision per explicit
  user request; hour/day formatting is already supported.
- **P3 menu whitespace:** retained capacity for multiple to-dos/reminders and the
  stable reflection area instead of resizing the panel as content changes.
- **Long-message screenshot follow-up:** moved the scroll hint to a separate layout
  row and explicitly clipped the scrolling viewport; its previous safe-area inset
  could overlap the last visible line.

## Remaining acceptance limits

Production Sparkle delivery requires signing/notarization and a published signed
feed. Real-calendar permissions, live calls in every browser/device combination,
VoiceOver end to end, audio quality, and every physical display/Spaces arrangement
are not implied by fixture tests. See VERIFICATION.md for reproducible checks.
