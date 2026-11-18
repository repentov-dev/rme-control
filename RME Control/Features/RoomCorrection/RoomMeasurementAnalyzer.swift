import Foundation

/// Сглаживание и объединение измеренных АЧХ.
enum RoomMeasurementAnalyzer {
    static let sampleRate: Double = 48_000
    static let sweepDuration: Double = 8
    static let sweepStart: Double = 20
    static let sweepEnd: Double = 20_000
    static let responsePoints = 240

    /// Средняя стерео-АЧХ по мощности.
    static func combined(_ left: [RoomResponsePoint], _ right: [RoomResponsePoint]) -> [RoomResponsePoint] {
        let rightByFrequency = Dictionary(uniqueKeysWithValues: right.map { ($0.frequency, $0.db) })
        return left.compactMap { point in
            guard let other = rightByFrequency[point.frequency] else { return nil }
            let power = (pow(10, point.db / 10) + pow(10, other / 10)) / 2
            return RoomResponsePoint(frequency: point.frequency, db: 10 * log10(max(power, 1e-12)))
        }
    }

    /// Средняя АЧХ по нескольким точкам, по мощности.
    static func average(_ curves: [[RoomResponsePoint]]) -> [RoomResponsePoint] {
        let nonEmpty = curves.filter { !$0.isEmpty }
        guard let first = nonEmpty.first else { return [] }
        guard nonEmpty.count > 1 else { return first }
        return first.indices.map { index in
            let frequency = first[index].frequency
            var power = 0.0
            var count = 0
            for curve in nonEmpty where curve.indices.contains(index) {
                power += pow(10, curve[index].db / 10)
                count += 1
            }
            let db = 10 * log10(max(power / Double(max(count, 1)), 1e-12))
            return RoomResponsePoint(frequency: frequency, db: db)
        }
    }

    /// Усреднение нескольких свипов: мощность по АЧХ, вектор по фазе.
    static func smoothed(_ points: [RoomResponsePoint], octaves: Double) -> [RoomResponsePoint] {
        guard points.count > 4, octaves > 0 else { return points }
        let grid = points.map(\.frequency)
        let values = points.map(\.db)
        let smoothed = smooth(values, grid: grid, octaves: octaves)
        return zip(grid, smoothed).map { RoomResponsePoint(frequency: $0.0, db: $0.1) }
    }

    static func logGrid() -> [Double] {
        (0..<responsePoints).map { index in
            20 * pow(1000, Double(index) / Double(responsePoints - 1))
        }
    }

    private static func interpolate(_ points: [(frequency: Double, db: Double)], frequency: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if frequency <= first.frequency { return first.db }
        if frequency >= last.frequency { return last.db }
        for index in 1..<points.count where frequency <= points[index].frequency {
            let left = points[index - 1]
            let right = points[index]
            let logLeft = log(left.frequency)
            let logRight = log(right.frequency)
            let t = (log(frequency) - logLeft) / (logRight - logLeft)
            return left.db + (right.db - left.db) * t
        }
        return last.db
    }

    private static func smooth(_ values: [Double], grid: [Double], octaves: Double) -> [Double] {
        let half = octaves / 2
        let logs = grid.map { log2($0) }
        return values.indices.map { index in
            var weight = 0.0
            var sum = 0.0
            for other in values.indices {
                let distance = abs(logs[other] - logs[index])
                guard distance <= half else { continue }
                let w = 1 - distance / max(half, 0.0001)
                weight += w
                sum += values[other] * w
            }
            return weight > 0 ? sum / weight : values[index]
        }
    }
}
