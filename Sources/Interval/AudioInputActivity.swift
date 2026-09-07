import CoreAudio
import Foundation
import Observation

/// Observes input-stream activity, never audio samples. Output-only playback does not count.
@MainActor @Observable final class AudioInputActivity {
  private(set) var isActive = false
  private var endedAt: Date?
  @ObservationIgnored private var processes: [AudioObjectID] = []
  @ObservationIgnored private var listeners: [Listener] = []

  private struct Listener {
    let object: AudioObjectID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
  }

  func start() {
    guard listeners.isEmpty else { return }
    let system = AudioObjectID(kAudioObjectSystemObject)
    listen(to: system, selector: kAudioHardwarePropertyProcessObjectList, rebuild: true)
    listen(to: system, selector: kAudioHardwarePropertyServiceRestarted, rebuild: true)
    refreshProcesses()
  }

  deinit {
    for var listener in listeners {
      AudioObjectRemovePropertyListenerBlock(
        listener.object, &listener.address, .main, listener.block)
    }
  }

  func effectiveIdleSeconds(_ physicalIdle: TimeInterval, at date: Date) -> TimeInterval {
    if isActive { return 0 }
    return max(0, min(physicalIdle, endedAt.map { date.timeIntervalSince($0) } ?? physicalIdle))
  }

  func update(isActive active: Bool, at date: Date) {
    guard active != isActive else { return }
    if !active { endedAt = date }
    isActive = active
  }

  private func refreshProcesses() {
    // Processes can connect between the size and data queries. Keep the last valid
    // snapshot and its listeners if a transient read fails instead of declaring idle.
    guard let current = Self.readProcesses() else { return }
    let system = AudioObjectID(kAudioObjectSystemObject)
    for var listener in listeners where listener.object != system {
      AudioObjectRemovePropertyListenerBlock(
        listener.object, &listener.address, .main, listener.block)
    }
    listeners.removeAll { $0.object != system }
    processes = current
    for process in processes {
      listen(to: process, selector: kAudioProcessPropertyIsRunningInput, rebuild: false)
    }
    refreshActivity()
  }

  private static func readProcesses() -> [AudioObjectID]? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    for _ in 0..<3 {
      var address = address(kAudioHardwarePropertyProcessObjectList)
      var size: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
        continue
      }
      if size == 0 { return [] }
      var objects = [AudioObjectID](
        repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
      let status = objects.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
      }
      if status == noErr {
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
      }
    }
    return nil
  }

  private func refreshActivity() {
    let active = processes.contains { process in
      var address = Self.address(kAudioProcessPropertyIsRunningInput)
      var running: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size)
      return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr
        && running != 0
    }
    update(isActive: active, at: Date())
  }

  private func listen(
    to object: AudioObjectID, selector: AudioObjectPropertySelector, rebuild: Bool
  ) {
    var address = Self.address(selector)
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      // Core Audio delivers this listener on the main queue supplied below.
      MainActor.assumeIsolated {
        if rebuild { self?.refreshProcesses() } else { self?.refreshActivity() }
      }
    }
    if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
      listeners.append(Listener(object: object, address: address, block: block))
    }
  }

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }
}
