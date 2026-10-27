import Foundation
import IOKit
import IOKit.hid

/// Raw HID transport for an Ajazz / Mirabox "Stream Dock" control interface.
///
/// These devices expose two HID interfaces on the same VID/PID:
///   * usage page 0x0001 / usage 0x0006 — a plain boot keyboard (used when a key
///     is configured to emit keystrokes directly in the vendor firmware)
///   * usage page 0xFFA0 / usage 0x0001 — the vendor control interface, which is
///     the one we drive. It declares a 512-byte input report and a 1024-byte
///     output report, both with report ID 0.
public final class HIDTransport {
    public struct Match {
        public let vendorID: Int
        public let productID: Int
        public let usagePage: Int
        public let usage: Int
        public init(vendorID: Int = 0x0300, productID: Int = 0x3002,
                    usagePage: Int = 0xFFA0, usage: Int = 0x0001) {
            self.vendorID = vendorID; self.productID = productID
            self.usagePage = usagePage; self.usage = usage
        }
    }

    public struct Info {
        public let vendorID: Int
        public let productID: Int
        public let product: String
        public let manufacturer: String
        public let serialNumber: String
        public let maxInputReportSize: Int
        public let maxOutputReportSize: Int
    }

    private let device: IOHIDDevice
    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private let inputBufferSize: Int
    private var runLoopScheduled = false

    /// Called on the scheduled run loop for every input report.
    public var onInputReport: (([UInt8]) -> Void)?

    public let info: Info

    private init(device: IOHIDDevice, info: Info) {
        self.device = device
        self.info = info
        self.inputBufferSize = max(info.maxInputReportSize, 512)
        self.inputBuffer = .allocate(capacity: inputBufferSize)
        self.inputBuffer.initialize(repeating: 0, count: inputBufferSize)
    }

    deinit {
        inputBuffer.deallocate()
    }

    // MARK: - Discovery

    private static func intProperty(_ d: IOHIDDevice, _ key: String) -> Int {
        guard let v = IOHIDDeviceGetProperty(d, key as CFString) as? Int else { return -1 }
        return v
    }
    private static func stringProperty(_ d: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(d, key as CFString) as? String) ?? ""
    }

    /// Every HID interface matching `match` (there is normally exactly one).
    public static func discover(_ match: Match = Match()) -> [HIDTransport] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: match.vendorID,
            kIOHIDProductIDKey: match.productID,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        return set.compactMap { d in
            guard intProperty(d, kIOHIDPrimaryUsagePageKey) == match.usagePage,
                  intProperty(d, kIOHIDPrimaryUsageKey) == match.usage else { return nil }
            let info = Info(
                vendorID: intProperty(d, kIOHIDVendorIDKey),
                productID: intProperty(d, kIOHIDProductIDKey),
                product: stringProperty(d, kIOHIDProductKey),
                manufacturer: stringProperty(d, kIOHIDManufacturerKey),
                serialNumber: stringProperty(d, kIOHIDSerialNumberKey),
                maxInputReportSize: intProperty(d, kIOHIDMaxInputReportSizeKey),
                maxOutputReportSize: intProperty(d, kIOHIDMaxOutputReportSizeKey))
            return HIDTransport(device: d, info: info)
        }
    }

    /// All HID interfaces on the given VID/PID, regardless of usage — for diagnostics.
    public static func discoverAllInterfaces(vendorID: Int = 0x0300,
                                             productID: Int = 0x3002) -> [(usagePage: Int, usage: Int, info: Info)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map { d in
            (intProperty(d, kIOHIDPrimaryUsagePageKey),
             intProperty(d, kIOHIDPrimaryUsageKey),
             Info(vendorID: intProperty(d, kIOHIDVendorIDKey),
                  productID: intProperty(d, kIOHIDProductIDKey),
                  product: stringProperty(d, kIOHIDProductKey),
                  manufacturer: stringProperty(d, kIOHIDManufacturerKey),
                  serialNumber: stringProperty(d, kIOHIDSerialNumberKey),
                  maxInputReportSize: intProperty(d, kIOHIDMaxInputReportSizeKey),
                  maxOutputReportSize: intProperty(d, kIOHIDMaxOutputReportSizeKey)))
        }
    }

    // MARK: - Lifecycle

    public enum TransportError: Error, CustomStringConvertible {
        case openFailed(IOReturn)
        case writeFailed(IOReturn)
        public var description: String {
            switch self {
            case .openFailed(let r):  return "IOHIDDeviceOpen failed: 0x\(String(r, radix: 16))"
            case .writeFailed(let r): return "IOHIDDeviceSetReport failed: 0x\(String(r, radix: 16))"
            }
        }
    }

    public func open(seize: Bool = false) throws {
        let opts = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        let r = IOHIDDeviceOpen(device, opts)
        guard r == kIOReturnSuccess else { throw TransportError.openFailed(r) }
    }

    public func close() {
        if runLoopScheduled {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            runLoopScheduled = false
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Begin delivering input reports to `onInputReport` on the current run loop.
    public func startReading() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, inputBufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            me.onInputReport?(bytes)
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        runLoopScheduled = true
    }

    /// Pull an input report synchronously (HID GET_REPORT). The device answers
    /// a 21-byte request with its firmware version string.
    public func getInputReport(length: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: length)
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer { p in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 0, p.baseAddress!, &len)
        }
        guard r == kIOReturnSuccess else { return nil }
        return Array(buf.prefix(Int(len)))
    }

    // MARK: - Output

    /// Send one output report. `payload` is padded/truncated to the report size.
    public func write(_ payload: [UInt8]) throws {
        try write(payload, reportLength: max(info.maxOutputReportSize, 1))
    }

    /// Send one output report of an explicit length — used to probe which frame
    /// size the firmware actually accepts.
    public func write(_ payload: [UInt8], reportLength: Int) throws {
        let size = max(reportLength, 1)
        var frame = [UInt8](repeating: 0, count: size)
        let n = min(payload.count, size)
        if n > 0 { frame.replaceSubrange(0..<n, with: payload[0..<n]) }
        let r = frame.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf.baseAddress!, size)
        }
        guard r == kIOReturnSuccess else { throw TransportError.writeFailed(r) }
    }
}
