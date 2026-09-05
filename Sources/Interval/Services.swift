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
  func schedule(timer: TimerState) {
    guard let center else { return }
    center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    guard timer.status == .running, let deadline = timer.deadline else { return }
    let content = UNMutableNotificationContent()
    content.title = "\(timer.kind.title) complete"
    content.body =
      timer.kind == .focus ? "Time for a break." : "Time to focus."
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
    fallback?("\(timer.kind.title) complete")
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) { completionHandler([.banner, .sound]) }
}

@MainActor final class AmbientAudio {
  private var engine: AVAudioEngine?
  private var configurationObserver: NSObjectProtocol?
  var failure: ((String) -> Void)?
  func stop() {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    engine?.stop()
    engine = nil
  }
  func play(_ sound: AmbientSound, volume: Double) throws {
    stop()
    guard sound != .silence else { return }
    let engine = AVAudioEngine()
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
          buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value * Float(volume)
        }
      }
      return noErr
    }
    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    try engine.start()
    self.engine = engine
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.engine != nil else { return }
        self.stop()
        self.failure?(
          "Audio output changed. Ambient sound was stopped to avoid switching speakers unexpectedly."
        )
      }
    }
  }
}
