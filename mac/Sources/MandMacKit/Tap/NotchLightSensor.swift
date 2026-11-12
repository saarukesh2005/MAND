import Foundation

/// Something that produces light readings (the real notch sensor, or a test double).
public protocol LightSource: AnyObject, Sendable {
    var isAvailable: Bool { get }
    /// Starts delivering readings on `queue` (about every 50 ms) until `stop()`.
    func start(on queue: DispatchQueue, _ onSample: @escaping @Sendable (LightSample) -> Void)
    func stop()
}

/// The ambient light sensor next to the camera in a MacBook's notch.
///
/// macOS has no public API for it, so this uses the private IOHIDEventSystemClient functions via `dlopen`
/// (the approach TapDrop uses, MIT). If a macOS update removes them, `isAvailable` is false and Tap to Send
/// says so; nothing else in M’AND depends on this. Readings are only taken while Tap to Send is on and a
/// capable phone is connected.
public final class NotchLightSensor: LightSource, @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static var matching: CFDictionary { ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 4] as CFDictionary } // Apple vendor page, ALS
    private static let eventType: Int64 = 12            // kIOHIDEventTypeAmbientLightSensor
    private static let levelField = Int32(12 << 16)     // kIOHIDEventFieldAmbientLightSensorLevel
    static let pollInterval: TimeInterval = 0.05

    private var client: AnyObject?
    private var service: AnyObject?
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    public private(set) var isAvailable = false

    public init() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreate"),
              let m = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let s = dlsym(h, "IOHIDEventSystemClientCopyServices"),
              let e = dlsym(h, "IOHIDServiceClientCopyEvent"),
              let f = dlsym(h, "IOHIDEventGetFloatValue") else { return }
        let create = unsafeBitCast(c, to: CreateFn.self)
        let setMatching = unsafeBitCast(m, to: SetMatchingFn.self)
        let copyServices = unsafeBitCast(s, to: CopyServicesFn.self)
        copyEvent = unsafeBitCast(e, to: CopyEventFn.self)
        getFloat = unsafeBitCast(f, to: GetFloatFn.self)
        guard let cl = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        setMatching(cl, Self.matching)
        client = cl
        service = (copyServices(cl)?.takeRetainedValue() as? [AnyObject])?.first
        isAvailable = service != nil && read() != nil
    }

    /// One reading in lux (0 when the lid is closed or the room is pitch dark), or nil if unavailable.
    public func read() -> Double? {
        guard let service, let copyEvent, let getFloat,
              let event = copyEvent(service, Self.eventType, 0, 0)?.takeRetainedValue() else { return nil }
        return getFloat(event, Self.levelField)
    }

    public func start(on queue: DispatchQueue, _ onSample: @escaping @Sendable (LightSample) -> Void) {
        lock.withLock {
            guard timer == nil, isAvailable else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(5))
            t.setEventHandler { [weak self] in
                guard let lux = self?.read() else { return }
                onSample(LightSample(t: ProcessInfo.processInfo.systemUptime, lux: lux))
            }
            t.resume()
            timer = t
        }
    }

    public func stop() {
        lock.withLock {
            timer?.cancel()
            timer = nil
        }
    }
}
