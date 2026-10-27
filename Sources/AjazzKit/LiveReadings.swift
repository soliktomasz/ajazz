import Foundation
import AudioToolbox
import CoreAudio
import IOKit.ps

/// Reads the values live keys show. Main thread only; shell commands run in the
/// background and the key shows their latest output.
public final class LiveReadings {

    /// Shell commands rerun at most this often.
    static let shellInterval: TimeInterval = 5

    private var formatters: [String: DateFormatter] = [:]
    private let host = mach_host_self()
    private var lastCPUTicks: [UInt32]?
    private var shellOutput: [String: String] = [:]
    private var shellStarted: [String: Date] = [:]
    private var shellRunning: Set<String> = []

    public init() {}

    /// The text to show now, or nil while a reading isn't available yet.
    public func text(for live: LiveText, now: Date = Date()) -> String? {
        switch live.source {
        case .clock:   return clock(live.value, now)
        case .volume:  return Self.volume()
        case .audioOutput: return AudioDevices.defaultOutput()?.name
        case .cpu:     return cpu()
        case .battery: return Self.battery()
        case .shell:   return shell(live.value ?? "", now)
        }
    }

    // MARK: - Clock

    private func clock(_ format: String?, _ now: Date) -> String {
        let f = (format?.isEmpty == false) ? format! : "HH:mm"
        if let df = formatters[f] { return df.string(from: now) }
        let df = DateFormatter()
        df.dateFormat = f
        formatters[f] = df
        return df.string(from: now)
    }

    // MARK: - CPU

    /// Load since the previous call, so the first call has nothing to compare.
    private func cpu() -> String? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let ticks = [t.0, t.1, t.2, t.3]
        defer { lastCPUTicks = ticks }
        guard let prev = lastCPUTicks, let pct = Self.cpuPercent(from: prev, to: ticks) else { return nil }
        return "\(pct)%"
    }

    /// Busy share between two tick samples ordered user, system, idle, nice.
    static func cpuPercent(from a: [UInt32], to b: [UInt32]) -> Int? {
        let d = zip(a, b).map { Double($1 &- $0) }  // the counters wrap
        let total = d.reduce(0, +)
        guard total > 0 else { return nil }
        return Int(((total - d[Int(CPU_STATE_IDLE)]) / total * 100).rounded())
    }

    // MARK: - Volume

    static func volume() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                         0, nil, &size, &device) == noErr else { return nil }

        addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr, muted != 0 {
            return "Muted"
        }
        // Devices without a software volume (some HDMI outputs) have no reading.
        addr.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        var level: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr else { return nil }
        return "\(Int((level * 100).rounded()))%"
    }

    // MARK: - Battery

    /// Nil on a Mac without a battery.
    static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return "\(current * 100 / max)%"
        }
        return nil
    }

    // MARK: - Shell

    private func shell(_ command: String, _ now: Date) -> String? {
        guard !command.isEmpty else { return nil }
        if !shellRunning.contains(command),
           now.timeIntervalSince(shellStarted[command] ?? .distantPast) >= Self.shellInterval {
            shellRunning.insert(command)
            shellStarted[command] = now
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let out = Self.firstLine(of: command)
                DispatchQueue.main.async {
                    self?.shellOutput[command] = out
                    self?.shellRunning.remove(command)
                }
            }
        }
        return shellOutput[command]
    }

    /// First non-empty output line of `command`. The shell is killed after 10 s so
    /// a hung command can't pile up.
    // shortcut: a background grandchild that keeps stdout open still blocks the
    // read, and that command stops refreshing; read with a deadline if it bites.
    static func firstLine(of command: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "error" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}
