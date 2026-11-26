import Darwin
import Foundation
import IOKit

/// Spots long file transfers: downloads and uploads over the internet or a
/// network share, and copies to or from an external drive or SD card.
///
/// Transfers barely use the CPU, so the app checks can't see them. Instead
/// this reads byte counters the system already keeps, with no permissions
/// needed:
///
/// - **Network:** the counters of the Mac's Wi-Fi and Ethernet connections
///   (what Activity Monitor's Network tab shows). This catches every app,
///   including Safari, whose downloads run in a separate system process.
/// - **Drives:** the read and write counters of external drives (USB,
///   Thunderbolt) and SD cards (what Activity Monitor's Disk tab shows). The
///   Mac's own disk is left out: it's busy all the time with ordinary work.
///
/// Light traffic (music, messages, small syncs, a drive being indexed for a
/// moment) stays under the thresholds, and a quick burst doesn't count: a
/// transfer has to keep going for about 10–15 seconds (see `BusyTracker`).
final class TransferMonitor {
    enum Kind: Equatable { case download, upload, driveCopy }

    struct Transfer: Equatable {
        let kind: Kind
        /// Bytes per second, averaged over the last reading.
        let rate: Double

        var title: String {
            switch kind {
            case .download: "Downloading"
            case .upload: "Uploading"
            case .driveCopy: "Copying files"
            }
        }
    }

    /// Network bytes per second, either direction, that count as a transfer.
    /// About 2 Mbit/s: well above music streaming or chat, low enough to
    /// catch a download on a slow connection.
    static let networkThreshold: Double = 250_000
    /// External drive bytes per second, read or write, that count as a copy.
    static let driveThreshold: Double = 1_000_000

    private let tracker = BusyTracker()
    private var lastNetwork: [String: (inBytes: UInt32, outBytes: UInt32)] = [:]
    private var lastDrives: [String: UInt64] = [:]
    private var lastReadAt: Date?
    private var lastRates: (down: Double, up: Double, drive: Double) = (0, 0, 0)
    private var busy: Set<String> = []

    /// The transfer in progress, or nil if nothing big is moving.
    func activeTransfer() -> Transfer? {
        let now = Date()
        // Readings closer than 2 seconds apart are too noisy to turn into a rate.
        if let last = lastReadAt, now.timeIntervalSince(last) >= 2 {
            let seconds = now.timeIntervalSince(last)
            let network = Self.readNetwork()
            let drives = Self.readDrives()
            var down: UInt64 = 0, up: UInt64 = 0, drive: UInt64 = 0
            for (name, c) in network {
                guard let old = lastNetwork[name] else { continue }
                // The network counters are 32-bit and wrap around after 4 GB.
                down += UInt64(c.inBytes &- old.inBytes)
                up += UInt64(c.outBytes &- old.outBytes)
            }
            for (name, total) in drives {
                guard let old = lastDrives[name], total >= old else { continue }
                drive += total - old
            }
            lastNetwork = network
            lastDrives = drives
            lastReadAt = now
            lastRates = (Double(down) / seconds, Double(up) / seconds, Double(drive) / seconds)
            busy = tracker.update([
                "net": max(lastRates.down, lastRates.up) >= Self.networkThreshold,
                "drive": lastRates.drive >= Self.driveThreshold,
            ])
        } else if lastReadAt == nil {
            lastNetwork = Self.readNetwork()
            lastDrives = Self.readDrives()
            lastReadAt = now
        }

        // A drive copy is the more specific answer when both are running.
        if busy.contains("drive") { return Transfer(kind: .driveCopy, rate: lastRates.drive) }
        if busy.contains("net") {
            return lastRates.up > lastRates.down
                ? Transfer(kind: .upload, rate: lastRates.up)
                : Transfer(kind: .download, rate: lastRates.down)
        }
        return nil
    }

    // MARK: - Network

    /// Byte counters for Wi-Fi and Ethernet ("en0", "en1"…). VPN tunnels,
    /// loopback and AirDrop links are left out so nothing is counted twice.
    private static func readNetwork() -> [String: (inBytes: UInt32, outBytes: UInt32)] {
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

    // MARK: - Drives

    /// Bytes read plus written so far, per external drive or SD card, keyed by
    /// its registry ID. Disk images and the Mac's built-in disk are skipped.
    private static func readDrives() -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return result }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard isRemovableDrive(service),
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }
            let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            result["\(id)"] = read &+ written
        }
        return result
    }

    /// External (USB, Thunderbolt, FireWire) drives and SD cards count.
    /// The built-in disk and disk images (".dmg", "Virtual Interface") don't.
    private static func isRemovableDrive(_ service: io_registry_entry_t) -> Bool {
        guard let protocolInfo = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "Protocol Characteristics" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        ) as? [String: Any] else { return false }
        let interconnect = protocolInfo["Physical Interconnect"] as? String ?? ""
        let location = protocolInfo["Physical Interconnect Location"] as? String ?? ""
        if interconnect == "Virtual Interface" || location == "File" { return false }
        return location == "External" || interconnect == "Secure Digital" || interconnect == "USB"
    }

    /// "4.2 MB/s"
    static func format(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
