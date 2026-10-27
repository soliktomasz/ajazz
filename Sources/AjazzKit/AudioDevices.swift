import CoreAudio
import Foundation

/// A sound output, identified by its UID, which survives reboots and replugging.
public struct AudioDevice: Equatable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
}

/// Lists and switches the system's default sound output.
public enum AudioDevices {

    /// Outputs macOS would offer in Sound settings, in system order.
    public static func outputs() -> [AudioDevice] {
        deviceIDs().compactMap { id in
            guard hasOutputStreams(id), canBeDefaultOutput(id),
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(id: id, uid: uid, name: name)
        }
    }

    public static func defaultOutput() -> AudioDevice? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr else { return nil }
        return outputs().first { $0.id == id }
    }

    /// False when that device isn't connected right now.
    @discardableResult
    public static func setDefaultOutput(uid: String) -> Bool {
        guard let device = outputs().first(where: { $0.uid == uid }) else { return false }
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        return AudioObjectSetPropertyData(system, &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }

    /// Switch to whichever of `a` / `b` isn't playing now; `a` if neither is.
    @discardableResult
    public static func toggleOutput(_ a: String, _ b: String) -> Bool {
        setDefaultOutput(uid: toggleTarget(current: defaultOutput()?.uid, a, b))
    }

    /// Step through every output, wrapping around.
    @discardableResult
    public static func cycleOutput(by steps: Int) -> Bool {
        guard let next = cycled(outputs().map(\.uid), current: defaultOutput()?.uid, by: steps) else { return false }
        return setDefaultOutput(uid: next)
    }

    static func toggleTarget(current: String?, _ a: String, _ b: String) -> String {
        current == a ? b : a
    }

    static func cycled(_ uids: [String], current: String?, by steps: Int) -> String? {
        guard !uids.isEmpty else { return nil }
        let here = current.flatMap { uids.firstIndex(of: $0) } ?? 0
        let n = uids.count
        return uids[((here + steps) % n + n) % n]
    }

    // MARK: - CoreAudio plumbing

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// Filters out the helper devices apps install that Sound settings hides.
    private static func canBeDefaultOutput(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
