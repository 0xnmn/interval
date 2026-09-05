import Foundation
import Testing

@testable import IntervalCore

@Suite("Timer engine") struct TimerEngineTests {
  let origin = Date(timeIntervalSince1970: 1_000)

  @Test func startUsesInjectedTime() {
    var timer = TimerState(kind: .focus, duration: 1_500)
    TimerEngine.start(&timer, now: origin)
    #expect(timer.deadline == origin.addingTimeInterval(1_500))
    TimerEngine.start(&timer, now: origin.addingTimeInterval(125))
    #expect(timer.deadline == origin.addingTimeInterval(1_500))
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

  @Test func legacyPausedStateRetainsSavedAccounting() {
    let timer = TimerState(
      kind: .focus, duration: 1_500, status: .paused, startedAt: origin,
      elapsedBeforePause: 150)
    #expect(TimerEngine.activeDuration(timer, now: origin.addingTimeInterval(1_050)) == 150)
    #expect(TimerEngine.remaining(timer, now: origin.addingTimeInterval(1_050)) == 1_350)
  }

  @Test func adjustingRemainingPreservesElapsedAndClamps() {
    var timer = TimerState(kind: .focus, duration: 1_500)
    TimerEngine.start(&timer, now: origin)
    TimerEngine.adjustRemaining(&timer, by: 300, now: origin.addingTimeInterval(100))
    #expect(timer.duration == 1_800)
    #expect(timer.deadline == origin.addingTimeInterval(1_800))
    TimerEngine.adjustRemaining(&timer, by: -10_000, now: origin.addingTimeInterval(200))
    #expect(timer.duration == 260)
    #expect(timer.deadline == origin.addingTimeInterval(260))
    #expect(TimerEngine.remaining(timer, now: origin.addingTimeInterval(200)) == 60)
  }

  @Test func removingTimeDuringFinalMinuteNeverExtendsTimer() {
    var timer = TimerState(kind: .shortBreak, duration: 300)
    TimerEngine.start(&timer, now: origin)
    let original = timer
    TimerEngine.adjustRemaining(&timer, by: -600, now: origin.addingTimeInterval(280))
    #expect(timer == original)
  }
}
