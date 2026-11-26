import Darwin
import Foundation

/// Spots long downloads and uploads: a big file in a browser, a video going
/// up to YouTube or Dropbox, a cloud folder syncing, a backup.
///
/// Transfers barely use the CPU, so the app checks can't see them. Instead
/// this reads the Mac's own byte counters for its Wi-Fi and Ethernet
/// connections (the numbers behind Activity Monitor's Network tab). That's
/// instant, needs no permissions, and catches every app, including Safari,
/// whose downloads run in a separate system process.
///
/// Light traffic (music, messages, small syncs) stays under the threshold,
/// and a quick burst doesn't count: the transfer has to keep going for
/// about 10–15 seconds (see `BusyTracker`).
final class NetworkMonitor {
    struct Transfer: Equatable {
        /// Bytes per second, averaged over the last reading.
        let bytesIn: Double
        let bytesOut: Double
        var isUpload: Bool { bytesOut > bytesIn }
        var rate: Double { max(bytesIn, bytesOut) }
    }

    /// Bytes per second in either direction that counts as a transfer.
    /// About 2 Mbit/s: well above music streaming or chat, low enough to
    /// catch a download on a slow connection.
    static let threshold: Double = 250_000

    private let tracker = BusyTracker()
    private var lastCounters: [String: (inBytes: UInt32, outBytes: UInt32)] = [:]
    private var lastReadAt: Date?
    private var lastRate = Transfer(bytesIn: 0, bytesOut: 0)

    /// The transfer in progress, or nil if nothing big is moving.
    func activeTransfer() -> Transfer? {
        let now = Date()
        // Readings closer than 2 seconds apart are too noisy to turn into a rate.
        if let last = lastReadAt, now.timeIntervalSince(last) < 2 {
            return tracker.update(["net": lastRate.rate >= Self.threshold]).isEmpty ? nil : lastRate
        }
        let counters = Self.readCounters()
        defer { lastCounters = counters; lastReadAt = now }
        guard let last = lastReadAt else { return nil }

        let seconds = now.timeIntervalSince(last)
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        for (name, c) in counters {
            guard let old = lastCounters[name] else { continue }
            // The counters are 32-bit and wrap around after 4 GB.
            totalIn += UInt64(c.inBytes &- old.inBytes)
            totalOut += UInt64(c.outBytes &- old.outBytes)
        }
        lastRate = Transfer(bytesIn: Double(totalIn) / seconds, bytesOut: Double(totalOut) / seconds)
        let busy = tracker.update(["net": lastRate.rate >= Self.threshold])
        return busy.isEmpty ? nil : lastRate
    }

    /// Byte counters for Wi-Fi and Ethernet ("en0", "en1"…). VPN tunnels,
    /// loopback and AirDrop links are left out so nothing is counted twice.
    private static func readCounters() -> [String: (inBytes: UInt32, outBytes: UInt32)] {
        var result: [String: (inBytes: UInt32, outBytes: UInt32)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = entry.ifa_data
            else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (data.ifi_ibytes, data.ifi_obytes)
        }
        return result
    }

    /// "4.2 MB/s"
    static func format(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
