import Foundation
import IOKit
import IOKit.hid

struct Vec3 {
  var x, y, z: Double
  static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
  var length: Double { (x * x + y * y + z * z).squareRoot() }
  func degrees(to o: Vec3) -> Double {
    let c = (x * o.x + y * o.y + z * o.z) / (length * o.length)
    return acos(max(-1, min(1, c))) * 180 / .pi
  }
}

/// "The laptop is being taken": it ends up clearly re-oriented, or it keeps moving for about a
/// second (lifted and carried). A bump, a knock series or a brief nudge that settles is ignored
/// on purpose (Allen, 2026-09-24: a short wobble that does not continue is safe).
/// Knobs are calibrated by hand with `guard-mode sensors`.
struct MotionDetector {
  var tiltLimit = 15.0        // degrees away from the orientation captured at arming
  var shakeLimit = 0.05       // g of acceleration beyond gravity that counts as moving
  var sustainFraction = 0.5   // share of the last `window` samples that must move (~1 s)
  var window = 268            // ~2 s at the sensor's ~134 Hz. Measured 2026-09-24: a single knock
                              // (0.85 g peak) rings ~0.3 s, two quick knocks tripped a 0.45 s window
  private(set) var gravity: Vec3?
  private var rest: Vec3?
  private var shaking: [Bool] = []

  /// Captures the current orientation as "at rest"; call once the laptop has settled.
  mutating func baseline() { rest = gravity; shaking.removeAll() }

  /// Feeds one sample in g; returns a reason once the laptop counts as moved.
  mutating func feed(_ a: Vec3) -> String? {
    guard let g = gravity else { gravity = a; return nil }
    let dynamic = (a - g).length
    // Slow low-pass (~1.5 s): a short knock barely moves it, so it cannot linger as fake shaking.
    gravity = Vec3(x: g.x + 0.005 * (a.x - g.x), y: g.y + 0.005 * (a.y - g.y), z: g.z + 0.005 * (a.z - g.z))
    guard let rest else { return nil }
    shaking.append(dynamic > shakeLimit)
    if shaking.count > window { shaking.removeFirst() }
    let tilt = gravity!.degrees(to: rest)
    if tilt > tiltLimit { return String(format: "电脑被倾斜 %.0f°", tilt) }
    let share = Double(shaking.filter { $0 }.count) / Double(window)
    if share >= sustainFraction { return String(format: "电脑在持续晃动（%.0f%% 采样超过 %.2fg）", share * 100, shakeLimit) }
    return nil
  }
}

/// Any lid movement beyond `limit` from the angle captured at arming.
struct LidDetector {
  var limit = 20.0
  private(set) var rest: Double?
  private(set) var last: Double?
  mutating func baseline() { rest = last }
  mutating func feed(_ angle: Double) -> String? {
    last = angle
    guard let rest, abs(rest - angle) >= limit else { return nil }
    return String(format: "屏幕开合角度 %.0f° → %.0f°", rest, angle)
  }
}

/// Lid angle and accelerometer of Apple Silicon MacBooks, read through the sensor processor's HID
/// devices. Neither needs root: the accelerometer only streams after `ReportInterval` is set on the
/// driver services (the wake sequence used by Bonk / Knock).
final class Sensors {
  var onAccel: ((Vec3) -> Void)?
  var onLid: ((Double) -> Void)?
  private(set) var accelReports = 0
  private(set) var lidReports = 0
  private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  private var buffers: [UnsafeMutablePointer<UInt8>] = []

  func start() {
    wake()
    IOHIDManagerSetDeviceMatchingMultiple(manager, [
      [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3, kIOHIDTransportKey: "SPU"],  // accelerometer
      [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A],  // lid angle ("las")
    ] as CFArray)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)  // keeps streaming while a menu is open
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    let me = Unmanaged.passUnretained(self).toOpaque()
    for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] {
      let size = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
      buffers.append(buffer)
      let isLid = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int == 0x8A
      IOHIDDeviceRegisterInputReportCallback(device, buffer, size, isLid ? lidReport : accelReport, me)
    }
  }

  // Lid report: [id, angle low byte, angle high byte], degrees.
  private let lidReport: IOHIDReportCallback = { ctx, _, _, _, _, r, n in
    guard n >= 3 else { return }
    let s = Unmanaged<Sensors>.fromOpaque(ctx!).takeUnretainedValue()
    s.lidReports += 1
    let raw = Double(UInt16(r[1]) | UInt16(r[2]) << 8)
    s.onLid?(raw > 180 ? raw - 360 : raw)  // a shut lid reads 359 for -1 (seen live 2026-09-24)
  }

  // Accelerometer report: x, y, z as little-endian Int32 at offsets 6, 10, 14, in 1/65536 g.
  private let accelReport: IOHIDReportCallback = { ctx, _, _, _, _, r, n in
    guard n >= 18 else { return }
    let s = Unmanaged<Sensors>.fromOpaque(ctx!).takeUnretainedValue()
    s.accelReports += 1
    func axis(_ o: Int) -> Double {
      Double(Int32(bitPattern: UInt32(r[o]) | UInt32(r[o + 1]) << 8 | UInt32(r[o + 2]) << 16 | UInt32(r[o + 3]) << 24)) / 65536
    }
    s.onAccel?(Vec3(x: axis(6), y: axis(10), z: axis(14)))
  }

  func stop() {
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    onAccel = nil
    onLid = nil
  }

  func wake() {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &it) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(it) }
    while case let s = IOIteratorNext(it), s != 0 {
      IORegistryEntrySetCFProperty(s, "ReportInterval" as CFString, 8000 as CFNumber)
      IOObjectRelease(s)
    }
  }
}
