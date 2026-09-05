import Foundation
import Testing
@testable import IntervalCore

@Suite("Timer engine") struct TimerEngineTests {
    let origin = Date(timeIntervalSince1970: 1_000)

    @Test func startPauseAndResumeUseInjectedTime() {
        var timer = TimerState(kind: .focus, duration: 1_500)
        TimerEngine.start(&timer, now: origin)
        #expect(timer.deadline == origin.addingTimeInterval(1_500))
        TimerEngine.pause(&timer, now: origin.addingTimeInterval(125))
        #expect(timer.status == .paused)
        #expect(timer.elapsedBeforePause == 125)
        TimerEngine.resume(&timer, now: origin.addingTimeInterval(500))
        #expect(timer.deadline == origin.addingTimeInterval(1_875))
    }

    @Test func completionIsIdempotent() {
        var timer = TimerState(kind: .focus, duration: 10)
        TimerEngine.start(&timer, now: origin)
        #expect(TimerEngine.reconcile(&timer, now: origin.addingTimeInterval(10)))
        #expect(timer.status == .completed)
        #expect(!TimerEngine.reconcile(&timer, now: origin.addingTimeInterval(20)))
        #expect(timer.completionRecorded)
    }

    @Test func abandonOnlyAffectsActiveTimer() {
        var ready = TimerState(kind: .shortBreak, duration: 300)
        TimerEngine.abandon(&ready)
        #expect(ready.status == .ready)
        TimerEngine.start(&ready, now: origin)
        TimerEngine.abandon(&ready)
        #expect(ready.status == .abandoned)
    }

    @Test func activeDurationExcludesPausedWallTime() {
        var timer = TimerState(kind: .focus, duration: 1_500)
        TimerEngine.start(&timer, now: origin)
        TimerEngine.pause(&timer, now: origin.addingTimeInterval(100))
        TimerEngine.resume(&timer, now: origin.addingTimeInterval(1_000))
        #expect(TimerEngine.activeDuration(timer, now: origin.addingTimeInterval(1_050)) == 150)
        TimerEngine.pause(&timer, now: origin.addingTimeInterval(1_050))
        #expect(timer.elapsedBeforePause == 150)
    }
}
