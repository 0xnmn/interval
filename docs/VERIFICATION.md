# Verification

## Executed locally

Environment: Apple silicon, macOS 26.6.2, Xcode 26.6, Swift 6.3.3.

- `swift test`: 33 tests pass across timer, reminder, calendar/persistence, and AppStore workflows.
- `scripts/build.sh`: builds the production executable and app bundle under macOS's bundled Bash.
- `codesign --verify --deep --strict .build/Interval.app`: validates the local ad-hoc app and embedded Sparkle code.
- `bash -n scripts/build.sh scripts/release.sh`: validates shell syntax.
- Invalid build versions/feed configuration are rejected; the release script refuses missing production credentials.
- Actual app-bundle launches produced native SwiftUI fixture captures for timer, paused timer, reflection, history, calendar settings, reminder editor, paused warning, floating/full-screen reminder, menu, and general/update settings.
- Independent adversarial code and design reviews were performed for the initial plan and each implementation phase, with fixes before moving forward.

## What the automated checks cover

Tests execute real state transitions and storage, including pause/resume/abandon; idempotent completion; four-session cadence; active time excluding pauses; subsecond persistence; unreadable-file protection; scratchpad/reflection persistence; calendar leap/month/time-zone and half-open overlap boundaries; calendar selection; idle-paused countdowns; suppression; recurrence coalescing; serialization; same-occurrence postponement; independent reminder CRUD; preview isolation; local export; and navigation stability.

## Limits, not implied passes

- Screen-recording access was unavailable. Native off-screen view rendering was used and inspected instead. Some AppKit-composited sidebar/glass layers do not appear fully in those bitmap captures.
- The test suite does not claim to have driven every control using macOS Accessibility automation, exercised VoiceOver end to end, or covered every physical display/notch/Spaces arrangement.
- Calendar tests use injected events; they do not imply access was granted to the user's real calendars. Calendar and notification permission prompts remain explicit user choices.
- Audible playback quality, physical headphone disconnect behavior, and real macOS lock/unlock edge cases need on-device acceptance testing.
- A production Sparkle upgrade was not executed: Developer ID, notarization credentials, and a published signed update feed are not available. Local signature validation is not Apple notarization.

## Acceptance checks for a signed distribution

1. Grant Calendar and Notifications access explicitly, then revoke each while running; confirm clear degraded states and no stale suppression.
2. Complete a focus from the menu bar, start the suggested break, and add feedback/journal without losing either state.
3. Type, scroll, and drag through a reminder deadline; the warning pauses and no takeover appears until idle. Postpone and confirm future recurrence is unchanged.
4. Preview/dismiss every template, edit emoji size/message/duration, and verify both floating and full-screen controls remain reachable.
5. Test sleep, lock/unlock, fast user switching, full-screen apps, display removal, and mixed-DPI/notched displays. Verify no reminder storm or keyboard trap.
6. Test VoiceOver, keyboard-only navigation, increased contrast, reduced transparency, and reduced motion.
7. Validate signed version N → N+1 updates with real Sparkle archives; installation must defer during running/paused timers or visible reminders and preserve all local data.
