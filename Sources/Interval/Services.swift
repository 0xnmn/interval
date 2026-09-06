import AVFoundation
import AppKit
import Foundation
import IntervalCore
import UserNotifications

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  var fallback: ((String) -> Void)?
  private let center: UNUserNotificationCenter?
  init(enabled: Bool = true) {
    center = enabled ? UNUserNotificationCenter.current() : nil
    super.init()
    center?.delegate = self
  }
  func status() async -> UNAuthorizationStatus {
    await center?.notificationSettings().authorizationStatus ?? .notDetermined
  }
  func request() async throws -> Bool {
    try await center?.requestAuthorization(options: [.alert, .sound]) ?? false
  }
  static func completionTitle(for kind: TimerKind) -> String {
    kind == .focus ? "How did that session feel?" : "Ready to focus?"
  }
  func schedule(timer: TimerState) {
    guard let center else { return }
    center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    guard timer.status == .running, let deadline = timer.deadline else { return }
    let content = UNMutableNotificationContent()
    content.title = Self.completionTitle(for: timer.kind)
    content.body =
      timer.kind == .focus
      ? "Your focus session ended. Take a moment to reflect."
      : "Your break is over. Return when you’re ready."
    content.sound = .default
    center.add(
      UNNotificationRequest(
        identifier: timer.id.uuidString, content: content,
        trigger: UNTimeIntervalNotificationTrigger(
          timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false))
    ) { [weak self] error in
      guard let error else { return }
      Task { @MainActor in
        self?.fallback?("Couldn’t schedule the completion alert: \(error.localizedDescription)")
      }
    }
  }
  func cancel(_ timer: TimerState) {
    center?.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
  }
  func completed(_ timer: TimerState) {
    // Do not remove the pending request here: completion can race the notification daemon.
    // The in-app completion is independent of system notification authorization.
    fallback?(Self.completionTitle(for: timer.kind))
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) { completionHandler([.banner, .sound]) }
}

@MainActor final class AmbientAudio {
  private static let gainRampDuration: TimeInterval = 0.15
  private static let gainRampSteps = 15

  private(set) var engine: AVAudioEngine?
  private var sound: AmbientSound?
  private var configurationObserver: NSObjectProtocol?
  private var configurationID: UUID?
  private var gainTask: Task<Void, Never>?
  private var retiredEngines: [UUID: AVAudioEngine] = [:]
  private var retirementTasks: [UUID: Task<Void, Never>] = [:]
  var failure: ((String) -> Void)?

  func stop() {
    removeConfigurationObserver()
    gainTask?.cancel()
    gainTask = nil
    retirementTasks.values.forEach { $0.cancel() }
    retirementTasks.removeAll()
    retiredEngines.values.forEach { $0.stop() }
    retiredEngines.removeAll()
    engine?.stop()
    engine = nil
    sound = nil
  }

  func play(_ sound: AmbientSound, volume: Double) throws {
    let volume = Float(max(0, min(1, volume)))
    if sound == self.sound, let engine {
      rampCurrentEngine(engine, to: volume)
      return
    }

    guard sound != .silence else {
      fadeOut()
      return
    }

    let newEngine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    var seed: UInt64 = 0x1234_5678
    var sample: Float = 0
    var phase: Float = 0
    let source = AVAudioSourceNode { _, _, frames, list -> OSStatus in
      let buffers = UnsafeMutableAudioBufferListPointer(list)
      for frame in 0..<Int(frames) {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        let white = Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
        let value: Float
        switch sound {
        case .brownNoise:
          sample = sample * 0.98 + white * 0.02
          value = sample * 3
        case .rain: value = white * (abs(white) > 0.72 ? 0.8 : 0.12)
        case .ocean:
          phase += 0.00012
          sample = sample * 0.96 + white * 0.04
          value = sample * (0.25 + 0.18 * sin(phase))
        case .silence: value = 0
        }
        for buffer in buffers {
          buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
        }
      }
      return noErr
    }
    newEngine.attach(source)
    newEngine.connect(source, to: newEngine.mainMixerNode, format: format)
    newEngine.mainMixerNode.outputVolume = 0
    do {
      try newEngine.start()
    } catch {
      // Match the previous fallback behavior: a failed replacement leaves no audio running.
      stop()
      throw error
    }

    fadeOut()
    engine = newEngine
    self.sound = sound
    let configurationID = UUID()
    self.configurationID = configurationID
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: newEngine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.configurationID == configurationID else { return }
        self.stop()
        self.failure?(
          "Audio output changed. Ambient sound was stopped to avoid switching speakers unexpectedly."
        )
      }
    }
    rampCurrentEngine(newEngine, to: volume)
  }

  private func removeConfigurationObserver() {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    configurationID = nil
  }

  private func rampCurrentEngine(_ engine: AVAudioEngine, to target: Float) {
    gainTask?.cancel()
    let start = engine.mainMixerNode.outputVolume
    gainTask = Task { @MainActor [weak self, weak engine] in
      guard let self, let engine else { return }
      await self.ramp(engine, from: start, to: target)
      if !Task.isCancelled, self.engine === engine {
        engine.mainMixerNode.outputVolume = target
        self.gainTask = nil
      }
    }
  }

  func fadeOut() {
    removeConfigurationObserver()
    gainTask?.cancel()
    gainTask = nil
    guard let oldEngine = engine else {
      sound = nil
      return
    }
    engine = nil
    sound = nil

    let id = UUID()
    retiredEngines[id] = oldEngine
    let start = oldEngine.mainMixerNode.outputVolume
    retirementTasks[id] = Task { @MainActor [weak self] in
      guard let self else {
        oldEngine.stop()
        return
      }
      await self.ramp(oldEngine, from: start, to: 0)
      oldEngine.stop()
      self.retiredEngines[id] = nil
      self.retirementTasks[id] = nil
    }
  }

  private func ramp(_ engine: AVAudioEngine, from start: Float, to target: Float) async {
    let delay = UInt64(
      Self.gainRampDuration * 1_000_000_000 / Double(Self.gainRampSteps))
    for step in 1...Self.gainRampSteps {
      do {
        try await Task.sleep(nanoseconds: delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      let progress = Float(step) / Float(Self.gainRampSteps)
      engine.mainMixerNode.outputVolume = start + (target - start) * progress
    }
  }
}
