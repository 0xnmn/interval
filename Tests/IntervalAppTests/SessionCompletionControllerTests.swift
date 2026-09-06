import AppKit
import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Session completion controller state")
struct SessionCompletionControllerTests {
  @Test func nativePromptExtendsThenTransitionsToReflectionAndCloses() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      runtimeEnabled: false)
    let now = Date()
    store.now = now
    store.data.activeTimer = TimerState(
      kind: .focus, duration: 1500, status: .running,
      startedAt: now.addingTimeInterval(-1444), deadline: now.addingTimeInterval(56))
    let controller = SessionCompletionController()
    defer { controller.close() }
    let original = Set(NSApp.windows.map(\.windowNumber))
    controller.update(store: store)
    let prompt = try #require(
      NSApp.windows.first { !original.contains($0.windowNumber) && $0.isVisible })
    #expect(!prompt.isKeyWindow)
    #expect(prompt.frame.size == SessionCompletionController.almostTimeSize)
    store.adjustCurrentTime(by: 300, at: now)
    controller.update(store: store)
    #expect(!prompt.isVisible)
    let deadline = try #require(store.timer.deadline)
    store.now = deadline.addingTimeInterval(-30)
    controller.update(store: store)
    #expect(NSApp.windows.contains { !original.contains($0.windowNumber) && $0.isVisible })
    store.reconcile(at: deadline)
    controller.update(store: store)
    let completion = try #require(
      NSApp.windows.first { !original.contains($0.windowNumber) && $0.isVisible })
    #expect(completion.frame.size == SessionCompletionController.toastSize)
    #expect(store.completionSessionID != nil)
    store.continueAfterReflection(at: deadline)
    controller.update(store: store)
    #expect(!completion.isVisible)
  }

  @Test func almostTimeOnlyAppearsDuringRunningFocusFinalMinute() {
    var state = SessionCompletionController.AlmostTimeState()
    var timer = TimerState(kind: .focus, duration: 1_500, status: .running)

    #expect(!present(&state, timer, 61))
    #expect(present(&state, timer, 60))
    #expect(present(&state, timer, 1))
    #expect(!present(&state, timer, 0))

    timer.kind = .shortBreak
    #expect(!present(&state, timer, 30))
    timer.kind = .focus
    timer.status = .paused
    #expect(!present(&state, timer, 30))
  }

  @Test func escapeSuppressesOneApproachButExtensionAllowsAnother() {
    var state = SessionCompletionController.AlmostTimeState()
    let timer = TimerState(kind: .focus, duration: 1_500, status: .running)

    #expect(present(&state, timer, 45))
    state.suppress()
    #expect(!present(&state, timer, 30))
    #expect(!present(&state, timer, 120))
    #expect(present(&state, timer, 60))
  }

  @Test func changingTimerClearsEscapeSuppression() {
    var state = SessionCompletionController.AlmostTimeState()
    let first = TimerState(kind: .focus, duration: 1_500, status: .running)
    let second = TimerState(kind: .focus, duration: 1_500, status: .running)

    #expect(present(&state, first, 30))
    state.suppress()
    #expect(!present(&state, first, 20))
    #expect(present(&state, second, 20))
  }

  private func present(
    _ state: inout SessionCompletionController.AlmostTimeState, _ timer: TimerState,
    _ remaining: TimeInterval
  ) -> Bool {
    state.shouldPresent(timer: timer, remaining: remaining)
  }
}
