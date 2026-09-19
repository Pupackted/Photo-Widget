import Foundation

/// Decides which photo a widget shows at any moment. Pure and deterministic, so the app's
/// previews and the widget extension always agree without sharing any runtime state.
nonisolated enum PhotoSchedule {

    static func index(for config: PhotoWidgetConfig, at date: Date, offset: Int = 0) -> Int {
        let count = config.photos.count
        guard count > 1 else { return 0 }

        // A widget that never rotates stays on its cover until tapped.
        guard config.rotation != .never else { return mod(offset, count) }

        let step = slot(at: date, interval: config.rotation) + offset
        switch config.order {
        case .inOrder:
            return mod(step, count)
        case .shuffle:
            let cycle = floorDiv(step, count)
            return shuffled(count: count, seed: seed(for: config.id), cycle: cycle)[mod(step, count)]
        }
    }

    /// Dates at which the widget should show a new photo, starting with `date` itself.
    static func entryDates(from date: Date, interval: RotationInterval, limit: Int = 48, calendar: Calendar = .current) -> [Date] {
        var dates = [date]
        guard interval != .never else { return dates }
        var cursor = date
        while dates.count < limit, let next = nextChange(after: cursor, interval: interval, calendar: calendar) {
            dates.append(next)
            cursor = next
        }
        return dates
    }

    static func nextChange(after date: Date, interval: RotationInterval, calendar: Calendar = .current) -> Date? {
        switch interval {
        case .never:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        default:
            guard let seconds = interval.seconds else { return nil }
            let zoneOffset = Double(calendar.timeZone.secondsFromGMT(for: date))
            let next = (floor((date.timeIntervalSince1970 + zoneOffset) / seconds) + 1) * seconds
            return Date(timeIntervalSince1970: next - zoneOffset)
        }
    }

    /// Monotonic counter that ticks once per interval, aligned to the local clock
    /// (on the hour, at midnight, …) so changes happen at predictable moments.
    static func slot(at date: Date, interval: RotationInterval, calendar: Calendar = .current) -> Int {
        switch interval {
        case .never:
            return 0
        case .daily:
            return calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        default:
            guard let seconds = interval.seconds else { return 0 }
            let zoneOffset = Double(calendar.timeZone.secondsFromGMT(for: date))
            return Int(floor((date.timeIntervalSince1970 + zoneOffset) / seconds))
        }
    }

    // MARK: - Shuffle

    /// A fresh permutation per cycle so every photo appears once before any repeats,
    /// and a cycle never starts with the photo the previous one ended on.
    private static func shuffled(count: Int, seed: UInt64, cycle: Int) -> [Int] {
        var order = permutation(count: count, seed: seed &+ UInt64(bitPattern: Int64(cycle)) &* 0x9E37_79B9_7F4A_7C15)
        let previous = permutation(count: count, seed: seed &+ UInt64(bitPattern: Int64(cycle - 1)) &* 0x9E37_79B9_7F4A_7C15)
        if order.first == previous.last, count > 1 { order.swapAt(0, 1) }
        return order
    }

    private static func permutation(count: Int, seed: UInt64) -> [Int] {
        var generator = SplitMix64(state: seed)
        var values = Array(0..<count)
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = Int(generator.next() % UInt64(i + 1))
            values.swapAt(i, j)
        }
        return values
    }

    private static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) }
    }

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
    private static func floorDiv(_ a: Int, _ n: Int) -> Int { Int(floor(Double(a) / Double(n))) }
}

private nonisolated struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
