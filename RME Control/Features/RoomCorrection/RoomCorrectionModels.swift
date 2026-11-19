import Foundation

/// Канал, для которого считается коррекция.
enum RoomCorrectionChannel: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right
    case stereo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        case .stereo: return String(localized: "Stereo")
        }
    }
}

/// Точка измеренной или предсказанной АЧХ.
struct RoomResponsePoint: Identifiable, Codable, Sendable, Equatable {
    let frequency: Double
    let db: Double

    var id: Double { frequency }
}

/// Кривая одного замера с фазой для roomeq.
struct RoomMeasurementCurve: Sendable {
    var points: [RoomResponsePoint]
    var phaseDegrees: [Double] = []
}

/// Параметры одного фильтра, приведённые к полосам Room EQ.
struct RoomCorrectionBand: Codable, Sendable, Equatable {
    var frequency: Double
    var gain: Double
    var q: Double
    /// 0 — bell, 1 — low/high shelf в зависимости от номера полосы.
    var type: Int
}

/// Целевая кривая. Для студии по умолчанию ровная.
struct RoomCorrectionTarget: Sendable {
    var tiltDBPerOctave: Double = 0
    var referenceFrequency: Double = 1_000

    func db(at frequency: Double) -> Double {
        tiltDBPerOctave * log2(frequency / referenceFrequency)
    }
}

/// Готовая коррекция для одного канала или общей стереопары.
struct RoomCorrection: Identifiable, Codable, Sendable {
    let channel: RoomCorrectionChannel
    var bands: [RoomCorrectionBand]
    /// Запас, который нужно выставить в Volume Calibration.
    var preamp: Double
    var measured: [RoomResponsePoint]
    var predicted: [RoomResponsePoint]
    /// СКО остаточной ошибки, дБ.
    var residualRMS: Double
    /// roomeq принял коррекцию; false — его политика оставила ответ без изменений.
    var engineAccepted: Bool = true
    /// Сколько фильтров движка не поместилось в девять полос Room EQ.
    /// Optional, чтобы старые файлы результатов продолжали читаться.
    var droppedFilters: Int?

    var id: String { channel.rawValue }
}

/// Одна точка прослушивания: левый и правый динамик.
struct RoomPositionMeasurement: Identifiable, Sendable {
    let index: Int
    var left: [RoomResponsePoint]
    var right: [RoomResponsePoint]
    /// Все свипы, которые отдаются roomeq для этой позиции.
    var leftCurves: [RoomMeasurementCurve] = []
    var rightCurves: [RoomMeasurementCurve] = []
    var sampleRate: Double = 48_000

    var id: Int { index }
}



/// Файл результата калибровки: полосы и калибровка громкости.
struct RoomCalibrationResult: Codable, Sendable {
    var version: Int = 1
    var createdAt: Date = .now
    var outputLabel: String
    var outputAddress: String
    var targetTilt: Double
    /// Зерно оптимизации: с ним пересчёт с тем же замером даёт тот же результат.
    var seed: Int?
    var corrections: [RoomCorrection]
}

/// Калибровочный файл микрофона.
struct MicCalibration: Sendable {
    var name: String
    var points: [RoomResponsePoint]

    static func load(from url: URL) throws -> MicCalibration {
        let text = try String(contentsOf: url, encoding: .utf8)
        var points: [RoomResponsePoint] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" || $0 == " " })
            guard parts.count >= 2,
                  let frequency = Double(parts[0]),
                  let db = Double(parts[1]),
                  frequency > 0 else { continue }
            points.append(RoomResponsePoint(frequency: frequency, db: db))
        }
        guard points.count >= 2 else {
            throw NSError(domain: "MicCalibration", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "The calibration file has no frequency/dB pairs.")
            ])
        }
        points.sort { $0.frequency < $1.frequency }
        return MicCalibration(name: url.lastPathComponent, points: points)
    }

    func correction(at frequency: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if frequency <= first.frequency { return first.db }
        if frequency >= last.frequency { return last.db }
        for index in 1..<points.count {
            let right = points[index]
            if frequency <= right.frequency {
                let left = points[index - 1]
                let span = right.frequency - left.frequency
                guard span > 0 else { return right.db }
                let t = (frequency - left.frequency) / span
                return left.db + (right.db - left.db) * t
            }
        }
        return 0
    }
}

/// Пользовательский пресет Room EQ.
struct RoomEQUserPreset: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var mode: String
    var bands: [RoomEQPresetBand]
    var preamp: Double
    var delayLeft: Double?
    var delayRight: Double?
    var calibrationLeft: Double?
    var calibrationRight: Double?
}
