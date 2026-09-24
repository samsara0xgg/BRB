import AVFoundation
import AudioToolbox
import CoreAudio

/// Plays straight to the built-in speakers (not the system output, so AirPods or a Multi-Output
/// Device cannot swallow it) and pins their volume and mute every half second, so whatever the
/// owner set beforehand does not matter. The owner's volume and mute come back on `stop()`.
final class Alarm {
  enum Level { case soft, loud }
  static let softVolume: Float32 = 0.35

  private let device: AudioDeviceID
  private let engine = AVAudioEngine()
  private let synth = Synth()
  private var timer: Timer?
  private var saved: (volume: Float32, mute: UInt32)?
  private var configured = false
  /// The owner's volume and mute, on disk while an alarm runs, so a crash or kill cannot turn the
  /// forced alarm level into "the owner's setting".
  static let savedFile = GuardApp.supportDir.appendingPathComponent("volume")

  init?() {
    guard let d = Alarm.builtInSpeakers() else { return nil }
    device = d
  }

  var isPlaying: Bool { timer != nil }

  func play(_ level: Level) throws {
    synth.loud = level == .loud
    if saved == nil {
      saved = Alarm.readSaved() ?? (Alarm.get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)),
                                    Alarm.get(device, kAudioDevicePropertyMute, UInt32(0)))
      try? FileManager.default.createDirectory(at: GuardApp.supportDir, withIntermediateDirectories: true)
      try? "\(saved!.volume) \(saved!.mute)".write(to: Alarm.savedFile, atomically: true, encoding: .utf8)
    }
    if !configured {
      try engine.outputNode.auAudioUnit.setDeviceID(device)
      let format = engine.outputNode.outputFormat(forBus: 0)
      let rate = format.sampleRate
      let node = AVAudioSourceNode { [synth] _, _, frames, list in
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for i in 0..<Int(frames) {
          let v = synth.next(rate: rate)
          for b in buffers { b.mData!.assumingMemoryBound(to: Float.self)[i] = v }
        }
        return noErr
      }
      engine.attach(node)
      engine.connect(node, to: engine.outputNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: format.channelCount))
      configured = true
    }
    pin()
    if !engine.isRunning { try engine.start() }
    timer?.invalidate()
    let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.pin() }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    engine.stop()
    if let saved { Alarm.restore(device, saved) }
    saved = nil
  }

  /// Puts back the owner's volume left on disk by an alarm that never reached `stop()`.
  static func restoreLeftover() {
    guard let saved = readSaved(), let d = builtInSpeakers() else { return }
    log("restoring volume \(saved.volume), mute \(saved.mute) left by an interrupted alarm")
    restore(d, saved)
  }

  private static func restore(_ d: AudioDeviceID, _ saved: (volume: Float32, mute: UInt32)) {
    set(d, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, saved.volume)
    set(d, kAudioDevicePropertyMute, saved.mute)
    try? FileManager.default.removeItem(at: savedFile)
  }

  private static func readSaved() -> (volume: Float32, mute: UInt32)? {
    guard let parts = (try? String(contentsOf: savedFile, encoding: .utf8))?.split(separator: " "), parts.count == 2,
          let v = Float32(parts[0]), let m = UInt32(parts[1]) else { return nil }
    return (v, m)
  }

  private func pin() {
    Alarm.set(device, kAudioDevicePropertyMute, UInt32(0))
    Alarm.set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, synth.loud ? Float32(1) : Alarm.softVolume)
    if !engine.isRunning { try? engine.start() }
  }

  /// The built-in output device ("MacBook Pro Speakers"), whatever the current system output is.
  static func builtInSpeakers() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    let outputs = ids.filter {
      var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
      var n: UInt32 = 0
      AudioObjectGetPropertyDataSize($0, &a, 0, nil, &n)
      return n > 0 && get($0, kAudioDevicePropertyTransportType, UInt32(0), scope: kAudioObjectPropertyScopeGlobal) == kAudioDeviceTransportTypeBuiltIn
    }
    return outputs.first { name($0).contains("Speakers") } ?? outputs.first
  }

  static func name(_ d: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var n: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, &n) == noErr, let n else { return "?" }
    return n.takeRetainedValue() as String
  }

  static func volume(_ d: AudioDeviceID) -> Float32 { get(d, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)) }

  private static func get<T: BitwiseCopyable>(_ d: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> T {
    var a = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var v = initial
    var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v)
    return v
  }

  private static func set<T: BitwiseCopyable>(_ d: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T) {
    var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var v = value
    AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
  }
}

/// Soft: a short 880 Hz beep every second. Loud: a 650-1250 Hz wailing siren, overdriven for bite.
final class Synth {
  var loud = false
  private var phase = 0.0, t = 0.0

  func next(rate: Double) -> Float {
    t += 1 / rate
    let freq: Double, gain: Double
    if loud {
      let sweep = abs((t / 1.2).truncatingRemainder(dividingBy: 1) * 2 - 1)  // triangle 0...1, 1.2 s period
      freq = 650 + 600 * sweep
      gain = 1
    } else {
      freq = 880
      gain = t.truncatingRemainder(dividingBy: 1) < 0.15 ? 0.5 : 0
    }
    phase += 2 * .pi * freq / rate
    if phase > 2 * .pi { phase -= 2 * .pi }
    return Float(gain * tanh(3 * sin(phase)) / tanh(3))
  }
}
