import AVFoundation
import AppKit
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor @Suite("Motion and sound", .serialized)
struct MotionSoundTests {
  @Test func panelEntranceSettlesAndReducedMotionIsImmediate() async throws {
    _ = NSApplication.shared
    let panel = NSPanel(
      contentRect: NSRect(x: 100, y: 100, width: 250, height: 64),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer { panel.close() }
    panel.contentView = NSHostingView(rootView: Text("Look away"))
    IntervalMotion.reveal(panel, reduceMotion: false)
    #expect(panel.alphaValue < 1)
    panel.orderFrontRegardless()
    #expect(panel.isVisible)
    try await Task.sleep(for: .milliseconds(400))
    #expect(panel.alphaValue == 1)
    panel.orderOut(nil)
    IntervalMotion.reveal(panel, reduceMotion: true)
    panel.orderFrontRegardless()
    #expect(panel.isVisible)
    #expect(panel.alphaValue == 1)
  }

  @Test func sameSoundKeepsEngineAndGainRampsWithoutAudioOutput() async throws {
    let audio = AmbientAudio()
    defer { audio.stop() }
    // Start muted, then pause hardware rendering before checking gain changes.
    try audio.play(.rain, volume: 0)
    let engine = try #require(audio.engine)
    #expect(engine.isRunning)
    engine.pause()
    try audio.play(.rain, volume: 0.2)
    #expect(audio.engine === engine)
    #expect(engine.mainMixerNode.outputVolume < 0.2)
    try await Task.sleep(for: .milliseconds(250))
    #expect(abs(engine.mainMixerNode.outputVolume - 0.2) < 0.001)
    try audio.play(.rain, volume: 0.8)
    try audio.play(.rain, volume: 0.1)
    try await Task.sleep(for: .milliseconds(250))
    #expect(audio.engine === engine)
    #expect(abs(engine.mainMixerNode.outputVolume - 0.1) < 0.001)
    audio.fadeOut()
    #expect(audio.engine == nil)
    try await Task.sleep(for: .milliseconds(250))
    #expect(!engine.isRunning)
    #expect(engine.mainMixerNode.outputVolume == 0)
  }

  @Test func stopCancelsRetirementAndSoundSwitches() async throws {
    let audio = AmbientAudio()
    defer { audio.stop() }
    try audio.play(.brownNoise, volume: 0)
    let first = try #require(audio.engine)
    try audio.play(.ocean, volume: 0)
    let second = try #require(audio.engine)
    #expect(first !== second)
    audio.stop()
    try await Task.sleep(for: .milliseconds(250))
    #expect(audio.engine == nil)
    #expect(!first.isRunning && !second.isRunning)
    try audio.play(.silence, volume: 1)
    #expect(audio.engine == nil)
  }

  @Test func rapidSwitchesRetireOldEnginesWithoutStoppingReplacement() async throws {
    let audio = AmbientAudio()
    defer { audio.stop() }
    try audio.play(.rain, volume: 0)
    let first = try #require(audio.engine)
    try audio.play(.ocean, volume: 0)
    let second = try #require(audio.engine)
    try audio.play(.brownNoise, volume: 0)
    let current = try #require(audio.engine)
    try await Task.sleep(for: .milliseconds(300))
    #expect(!first.isRunning && !second.isRunning)
    #expect(current.isRunning)
    #expect(audio.engine === current)
  }

  @Test func configurationChangesIgnoreReplacedEngineAndStopCurrentEngine() async throws {
    let audio = AmbientAudio()
    defer { audio.stop() }
    var failures = 0
    audio.failure = { _ in failures += 1 }
    try audio.play(.rain, volume: 0)
    let first = try #require(audio.engine)
    // Queue the old observer's callback before replacing its configuration identity.
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: first)
    try audio.play(.ocean, volume: 0)
    let current = try #require(audio.engine)
    try await Task.sleep(for: .milliseconds(50))
    #expect(audio.engine === current)
    #expect(failures == 0)
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: current)
    try await Task.sleep(for: .milliseconds(50))
    #expect(audio.engine == nil)
    #expect(!current.isRunning && !first.isRunning)
    #expect(failures == 1)
  }

  @Test func reminderSoundsAndNotificationNamesAreConsistent() throws {
    for sound in ReminderSound.allCases where sound != .none {
      let cue = try #require(NSSound(named: NSSound.Name(sound.title)))
      let preview = try #require(cue.copy() as? NSSound)
      #expect(preview !== cue)
    }
    #expect(Destination.reminders.icon == "bell")
    #expect(ReminderPresentation.fullscreen.title == "Full screen")
    #expect(NotificationService.completionTitle(for: .focus) == "How did that session feel?")
    #expect(NotificationService.completionTitle(for: .shortBreak) == "Ready to focus?")
    #expect(NotificationService.completionTitle(for: .longBreak) == "Ready to focus?")
  }
}
