# Verification

## Reproducible local checks

Environment: Apple silicon, macOS 26, Xcode 26.6, Swift 6.3.3.

Latest product-review verification: **157 tests in 18 suites pass**. Release build
and ad-hoc signature verification pass. Light/dark native screenshots were
reviewed and recaptured after fixes. Movie capture failed on this run; motion
claims are limited to the executed native motion tests, not a reviewed recording.

- `swift test --no-parallel`: core state machines and native AppKit/SwiftUI tests.
- `scripts/build.sh`: release bundle, embedded Sparkle, ad-hoc signature validation.
- `git diff --check`: patch hygiene.
- `Interval --snapshot <path> --snapshot-scene <scene> --snapshot-appearance light|dark --snapshot-composited`:
  fixture data in native windows, captured by WindowServer. Never edits user data.
- `--snapshot-motion --snapshot <path.mov>` captures the actual entrance. Add
  `--snapshot-reduce-motion` to exercise the deterministic reduced-motion path.

Product-review captures/logs are under `.build/product-review/` and
`.build/product-*.log`. They are local artifacts, not committed assets.

## Current behavior covered by tests

- Focus completion automatically starts a break; optional reflection cannot block
  it. Saving or leaving reflection does not reset the break. Running-break time
  adjustments work while reflection is open.
- Break completion counts overtime; focus starts only on explicit Resume.
- No pause action; legacy paused data is recovered without inventing active time.
- One-hour planned-duration cap and hour/day formatting.
- Reminder recurrence coalescing, per-reminder idle debounce, mouse/typing warning
  suspension, microphone activity, and all-day-event exclusion.
- Real overlay lifecycle, preview dismissal, five-second skip guard, field focus,
  native scrolling, checklist keyboard editing, and persistence.
- Settings keyboard navigation and deep links to already-open Settings.
- Native notch hover/click/Escape, heads-up expiry, keyboard-held expansion,
  previous key-window restoration, and overtime pinning.
- Color math for seven phase hues: 4.5:1 normal / 7:1 increased contrast against
  the specified opaque surface, both themes. These ratios are not a certification
  of every translucent pixel over arbitrary wallpaper.
- One-shot motion, reduced-motion bypass, stable countdown updates, sound routing,
  native-notification request contents, and update deferral.

## Acceptance limits

The tests do not claim every control was driven with VoiceOver or every physical
display/Spaces configuration was exercised. Calendar tests inject events; real
permission prompts and browser microphone activity still merit on-device checks.
Playback tests are not a human evaluation of sound quality.

On this macOS version, constructing an accessibility-high-contrast NSAppearance
without changing the system setting resolves to the ordinary Aqua appearance.
Color tests explicitly exercise increased contrast; a native visual acceptance
check should enable Increase Contrast in System Settings. The agent does not
silently change the user's accessibility preferences for screenshots.

No production Sparkle upgrade has been executed: Developer ID, notarization, and
a published signed feed are not configured. Ad-hoc signature validation is not
Apple notarization.

## Release acceptance

1. Grant/revoke Calendar and Notifications; confirm clear degraded states.
2. Complete focus without reflection, adjust the running break, let it overrun,
   and Resume from main/menu/notch/notification. Verify one transition and no reset.
3. Type, move, and use a microphone through reminder deadlines; confirm suppression
   and no catch-up storm. Confirm all-day events never suppress reminders.
4. Preview templates and a maximum-length reminder; scroll to the last line,
   extend/skip, and verify Escape behavior and controls on small displays.
5. Test sleep, lock/unlock, multiple displays, full-screen apps, and display removal.
6. Test VoiceOver, keyboard-only use, Increase Contrast, Reduce Transparency,
   Reduce Motion, and live light/dark changes.
7. Validate signed version N → N+1 updates with a real feed, preserving all data
   and deferring installation during active timers/reminders/reflection.
