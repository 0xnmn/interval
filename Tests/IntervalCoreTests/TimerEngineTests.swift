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

  @Test func adjustingRemainingPreservesElapsedAndClamps() {
    var timer = TimerState(kind: .focus, duration: 1_500)
    TimerEngine.start(&timer, now: origin)
    TimerEngine.adjustRemaining(&timer, by: 300, now: origin.addingTimeInterval(100))
    #expect(timer.duration == 1_800)
    #expect(timer.deadline == origin.addingTimeInterval(1_800))
    TimerEngine.pause(&timer, now: origin.addingTimeInterval(200))
    TimerEngine.adjustRemaining(&timer, by: -10_000, now: origin.addingTimeInterval(300))
    #expect(timer.elapsedBeforePause == 200)
    #expect(timer.duration == 260)
    #expect(TimerEngine.remaining(timer, now: origin.addingTimeInterval(300)) == 60)
  }
}
