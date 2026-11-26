import Foundation

/// Turns noisy, moment-to-moment CPU readings into a steady busy/idle answer.
///
/// A single `ps` reading is a snapshot: an idle agent redrawing its screen,
/// or an app checking for updates, can jump above the threshold for a moment.
/// So something only *becomes* busy after it has been hot in most of the
/// recent readings (about 10–15 seconds of real work), and only *stops* being
/// busy once it has gone quiet in nearly all of them. Short pauses in real
/// work don't flip it back and forth.
final class BusyTracker {
    private let window: Int
    private let enterHits: Int
    private let exitHits: Int
    private let minInterval: TimeInterval

    private var history: [String: [Bool]] = [:]
    private var busy: Set<String> = []
    private var lastRound = Date.distantPast

    /// - Parameters:
    ///   - window: how many recent readings to remember.
    ///   - enterHits: hot readings (out of `window`) needed to become busy.
    ///   - exitHits: at or below this many hot readings, it's idle again.
    ///   - minInterval: readings closer together than this are not recorded,
    ///     so extra refreshes (a toggle flipped, the menu opened) don't count
    ///     as more evidence.
    init(window: Int = 5, enterHits: Int = 4, exitHits: Int = 1, minInterval: TimeInterval = 2) {
        self.window = window
        self.enterHits = enterHits
        self.exitHits = exitHits
        self.minInterval = minInterval
    }

    /// Records one round of readings (key → above the threshold right now)
    /// and returns the keys that count as busy. Keys missing from a round
    /// (the process ended, the app quit) are forgotten.
    func update(_ readings: [String: Bool]) -> Set<String> {
        let now = Date()
        guard now.timeIntervalSince(lastRound) >= minInterval else {
            return busy.intersection(readings.keys)
        }
        lastRound = now

        var newHistory: [String: [Bool]] = [:]
        var newBusy: Set<String> = []
        for (key, hot) in readings {
            var recent = history[key] ?? []
            recent.append(hot)
            if recent.count > window { recent.removeFirst(recent.count - window) }
            newHistory[key] = recent

            let hits = recent.filter { $0 }.count
            if busy.contains(key) {
                if hits > exitHits { newBusy.insert(key) }
            } else if hits >= enterHits {
                newBusy.insert(key)
            }
        }
        history = newHistory
        busy = newBusy
        return newBusy
    }
}
