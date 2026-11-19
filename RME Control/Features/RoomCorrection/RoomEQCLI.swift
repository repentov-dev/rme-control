import Foundation

/// Набор девяти полос, полученный от настоящего roomeq CLI.
struct RoomEQFilterSet: Sendable {
    var bands: [RoomCorrectionBand]
    var preamp: Double
    /// Усиление/калибровка, рассчитанные roomeq (gain-плагины).
    var gainDB: Double
    /// roomeq счёл коррекцию достаточно полезной и принял её.
    var accepted: Bool
    /// Фильтры, которые движок вернул, но девяти полос Room EQ не хватило.
    var dropped: Int = 0
}

enum RoomEQCLIError: LocalizedError {
    case binaryMissing
    case badMeasurement
    case failed(String)
    case noCorrection

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return String(localized: "A measurement engine is missing from this build.")
        case .badMeasurement:
            return String(localized: "The measurement is too short.")
        case .failed:
            // Текст движка уходит в системный лог при показе ошибки (MeasurementFailure).
            return String(localized: "Could not calculate the correction.")
        case .noCorrection:
            return String(localized: "The engine returned no correction.")
        }
    }
}

/// Обёртка над настоящим `roomeq` из pierreaubert/autoeq.
/// Никакой собственной эвристики: конфиг, оптимизация и фильтры — его.
enum RoomEQCLI {
    static func optimizePair(left: [RoomMeasurementCurve],
                             right: [RoomMeasurementCurve],
                             tilt: Double,
                             sampleRate: Double,
                             dimensions: RoomDimensions?,
                             seed: Int?,
                             positionCount: Int) async throws -> (left: RoomEQFilterSet, right: RoomEQFilterSet) {
        let holder = CancellableProcess()
        let work = Task(priority: .userInitiated) {
            try optimizePairSync(left: left, right: right, tilt: tilt,
                                 sampleRate: sampleRate, dimensions: dimensions,
                                 seed: seed, positionCount: positionCount,
                                 holder: holder)
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
            holder.terminate()
        }
    }

    static func optimizeSingle(measurements: [RoomMeasurementCurve],
                               tilt: Double,
                               sampleRate: Double,
                               dimensions: RoomDimensions?,
                               seed: Int?,
                               positionCount: Int) async throws -> RoomEQFilterSet {
        let holder = CancellableProcess()
        let work = Task(priority: .userInitiated) {
            try optimizeSingleSync(measurements: measurements, tilt: tilt,
                                   sampleRate: sampleRate, dimensions: dimensions,
                                   seed: seed, positionCount: positionCount,
                                   holder: holder)
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
            holder.terminate()
        }
    }

    static func predicted(measured: [RoomResponsePoint],
                          bands: [RoomCorrectionBand]) -> [RoomResponsePoint] {
        var state = RoomEQState()
        state.bands = bands.map {
            RoomEQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        return measured.map { point in
            RoomResponsePoint(frequency: point.frequency,
                              db: point.db + RoomEQResponse.totalDb(state: state, at: point.frequency))
        }
    }

    // MARK: - Synchronous implementation (runs off the main actor)

    /// Границы полосы коррекции. Те же числа уходят в конфиг roomeq.
    static let minFrequency = 20.0
    static let maxFrequency = 1_600.0

    private static func optimizePairSync(left: [RoomMeasurementCurve],
                                         right: [RoomMeasurementCurve],
                                         tilt: Double,
                                         sampleRate: Double,
                                         dimensions: RoomDimensions?,
                                         seed: Int?,
                                         positionCount: Int,
                                         holder: CancellableProcess) throws -> (left: RoomEQFilterSet, right: RoomEQFilterSet) {
        guard left.allSatisfy({ $0.points.count > 8 }), right.allSatisfy({ $0.points.count > 8 }),
              !left.isEmpty, !right.isEmpty else { throw RoomEQCLIError.badMeasurement }
        let config = try makeConfig(
            speakers: ["left": left, "right": right],
            system: ["model": "stereo", "speakers": ["L": "left", "R": "right"]],
            tilt: tilt,
            sampleRate: sampleRate,
            dimensions: dimensions,
            seed: seed,
            positionCount: positionCount
        )
        let output = try run(config: config, sampleRate: sampleRate, holder: holder)
        guard let channels = output["channels"] as? [String: Any] else {
            throw RoomEQCLIError.noCorrection
        }
        let leftChannel = channel(in: channels, preferred: ["L", "left", "Left"])
        let rightChannel = channel(in: channels, preferred: ["R", "right", "Right"])
        guard let leftChannel, let rightChannel else { throw RoomEQCLIError.noCorrection }
        let accepted = acceptance(from: output)
        return (try filterSet(from: leftChannel, accepted: accepted),
                try filterSet(from: rightChannel, accepted: accepted))
    }

    private static func optimizeSingleSync(measurements: [RoomMeasurementCurve],
                                           tilt: Double,
                                           sampleRate: Double,
                                           dimensions: RoomDimensions?,
                                           seed: Int?,
                                           positionCount: Int,
                                           holder: CancellableProcess) throws -> RoomEQFilterSet {
        guard !measurements.isEmpty, measurements.allSatisfy({ $0.points.count > 8 }) else {
            throw RoomEQCLIError.badMeasurement
        }
        let config = try makeConfig(
            speakers: ["mono": measurements],
            system: nil,
            tilt: tilt,
            sampleRate: sampleRate,
            dimensions: dimensions,
            seed: seed,
            positionCount: positionCount
        )
        let output = try run(config: config, sampleRate: sampleRate, holder: holder)
        guard let channels = output["channels"] as? [String: Any] else {
            throw RoomEQCLIError.noCorrection
        }
        guard let channel = channel(in: channels, preferred: ["mono", "stereo", "M"]) else {
            throw RoomEQCLIError.noCorrection
        }
        return try filterSet(from: channel, accepted: acceptance(from: output))
    }

    // MARK: - Config

    private static func makeConfig(speakers: [String: [RoomMeasurementCurve]],
                                   system: [String: Any]?,
                                   tilt: Double,
                                   sampleRate: Double,
                                   dimensions: RoomDimensions?,
                                   seed: Int?,
                                   positionCount: Int) throws -> [String: Any] {
        var config: [String: Any] = [
            "version": "3.0.0",
            "speakers": speakers.mapValues { measurements -> [String: Any] in
                let inline: [[String: Any]] = measurements.map { curve in
                    var item: [String: Any] = [
                        "name": UUID().uuidString,
                        "frequencies": curve.points.map(\.frequency),
                        // Наклон цели переносим в измерение: roomeq оптимизирует
                        // к плоской цели, а вычитание наклона даёт ту же коррекцию.
                        "magnitude_db": curve.points.map(\.db)
                    ]
                    return item
                }
                if inline.count == 1 { return ["inline": inline[0]] }
                return ["measurements": inline, "speaker_name": "RoomEQ"]
            },
            "optimizer": [
                // Настройки roomeq по его руководству. 9 фильтров ls-pk-hs —
                // единственное отступление: столько полос в TotalMix Room EQ.
                "algorithm": "autoeq:cmaes",
                "num_filters": 9,
                "peq_model": "ls-pk-hs",
                "min_freq": minFrequency,
                "max_freq": maxFrequency,
                "min_q": 0.5,
                "max_q": 3.0,
                "min_db": -12.0,
                "max_db": 4.0,
                "max_iter": 50_000,
                "population": 300,
                "refine": true,
                "local_algo": "cobyla",
                "psychoacoustic": true,
                "asymmetric_loss": true,
                "processing_mode": "low_latency",
                "allow_delay": false,
                // Целевой наклон считает сам roomeq, без нашей подмены кривой.
                "target_response": [
                    "shape": abs(tilt) > 0.01 ? "custom" : "flat",
                    "slope_db_per_octave": tilt,
                    "reference_freq": 1_000.0,
                    "preference": [
                        "bass_shelf_db": 0.0,
                        "bass_shelf_freq": 200.0,
                        "treble_shelf_db": 0.0,
                        "treble_shelf_freq": 8_000.0
                    ]
                ]
            ],
            "target_curve": "flat"
        ]
        if let system {
            config["system"] = system
        }
        if let seed {
            // Без зерна каждый пересчёт даёт другой результат: менять наклон и
            // сравнивать варианты становилось бы невозможно.
            var optimizer = config["optimizer"] as? [String: Any] ?? [:]
            optimizer["seed"] = seed
            config["optimizer"] = optimizer
        }

        var recording: [String: Any] = [
            "recording_sample_rate": sampleRate,
            "signal_type": "Sweep",
            // Длительность и число свипов должны совпадать с тем, что реально
            // делает sotf-capture: иначе движок отчитывается о другом замере.
            "signal_duration_secs": RoomMeasurementAnalyzer.captureDuration,
            "sweep_start_freq": RoomMeasurementAnalyzer.sweepStart,
            "sweep_end_freq": RoomMeasurementAnalyzer.sweepEnd,
            "num_sweeps": RoomMeasurementAnalyzer.sweepsPerChannel,
            "pre_silence_s": 2.0,
            "signal_level_db": -6.02,
            "num_positions": max(positionCount, 1),
            "channel_names": speakers.keys.sorted()
        ]
        if let dimensions, dimensions.length > 0, dimensions.width > 0, dimensions.height > 0 {
            recording["room_dimensions"] = [
                "length": dimensions.length,
                "width": dimensions.width,
                "height": dimensions.height
            ]
        }
        config["recording_config"] = recording

        return config
    }

    // MARK: - Process

    private static func run(config: [String: Any], sampleRate: Double,
                            holder: CancellableProcess) throws -> [String: Any] {
        guard let binary = binaryURL else { throw RoomEQCLIError.binaryMissing }
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("rme-roomeq-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let outputURL = directory.appendingPathComponent("output.json")
        let data = try JSONSerialization.data(withJSONObject: config, options: [])
        try data.write(to: configURL)

        let base = ["--config", configURL.path,
                    "--output", outputURL.path,
                    "--sample-rate", String(sampleRate)]

        // Проверка конфига самим движком: он же проверяет измерительные файлы
        // и объясняет ошибку внятнее, чем «файла результата нет».
        let dry = try execute(binary: binary, arguments: base + ["--dry-run"],
                              directory: directory, holder: holder)
        guard dry.status == 0 else { throw RoomEQCLIError.failed(dry.log) }
        try? fileManager.removeItem(at: outputURL)

        let run = try execute(binary: binary, arguments: base,
                              directory: directory, holder: holder)
        try Task.checkCancellation()
        guard run.status == 0 else { throw RoomEQCLIError.failed(run.log) }
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw RoomEQCLIError.noCorrection
        }
        let outputData = try Data(contentsOf: outputURL)
        guard let output = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw RoomEQCLIError.noCorrection
        }
        return output
    }

    /// Один запуск roomeq. stderr читается до конца процесса, чтобы длинный
    /// лог не заблокировал пайп.
    private static func execute(binary: URL, arguments: [String], directory: URL,
                                holder: CancellableProcess) throws -> (status: Int32, log: String) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(["RUST_LOG": "error"]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        holder.attach(process)
        try process.run()
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let log = String(decoding: errorData, as: UTF8.self)
        return (process.terminationStatus, String(log.suffix(1_200)))
    }

    private static var binaryURL: URL? {
        // Модуль замера может быть скачан отдельно — он важнее бандла.
        if let url = MeasurementModule.binary(named: "roomeq") {
            return url
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent("build/roomeq"),
            root.appendingPathComponent("RME Control/Resources/roomeq"),
            root.appendingPathComponent("vendor/roomeq")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Output

    private static func channel(in channels: [String: Any], preferred: [String]) -> [String: Any]? {
        for name in preferred {
            if let channel = channels[name] as? [String: Any] { return channel }
        }
        for (name, value) in channels {
            if preferred.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
               let channel = value as? [String: Any] {
                return channel
            }
        }
        return channels.values.compactMap { $0 as? [String: Any] }.first
    }

    private struct Filter {
        enum Kind { case lowShelf, peak, highShelf }
        var kind: Kind
        var frequency: Double
        var gain: Double
        var q: Double
    }

    private static func acceptance(from output: [String: Any]) -> Bool {
        guard let metadata = output["metadata"] as? [String: Any],
              let report = metadata["correction_acceptance"] as? [String: Any],
              let accepted = report["accepted"] as? Bool else { return true }
        return accepted
    }

    private static func filterSet(from channel: [String: Any], accepted: Bool) throws -> RoomEQFilterSet {
        let plugins = channel["plugins"] as? [[String: Any]] ?? []
        var filters: [Filter] = []
        for plugin in plugins {
            guard (plugin["plugin_type"] as? String) == "eq",
                  let parameters = plugin["parameters"] as? [String: Any],
                  let rawFilters = parameters["filters"] as? [[String: Any]] else { continue }
            for raw in rawFilters {
                guard let type = raw["filter_type"] as? String,
                      let frequency = number(raw["freq"]),
                      let gain = number(raw["db_gain"]),
                      let q = number(raw["q"]),
                      frequency.isFinite, gain.isFinite, q.isFinite else { continue }
                let kind: Filter.Kind
                switch type {
                case "lowshelf", "low_shelf": kind = .lowShelf
                case "highshelf", "high_shelf": kind = .highShelf
                default: kind = .peak
                }
                filters.append(Filter(kind: kind, frequency: frequency, gain: gain, q: q))
            }
        }

        var gainDB = 0.0
        for plugin in plugins where (plugin["plugin_type"] as? String) == "gain" {
            if let parameters = plugin["parameters"] as? [String: Any],
               let gain = number(parameters["gain_db"]) {
                gainDB += gain
            }
        }

        // Шельф, прижатый к границе полосы коррекции, — это не правка полосы,
        // а общий наклон всего, что за границей. Такой слот остаётся нейтральным.
        let lowShelf = filters.first { $0.kind == .lowShelf }
        let highShelf = filters.first { $0.kind == .highShelf }
        let lowShelfFits = lowShelf.map { abs(log2($0.frequency / minFrequency)) > 0.15 } ?? false
        let highShelfFits = highShelf.map { abs(log2($0.frequency / maxFrequency)) > 0.15 } ?? false
        var dropped = 0
        if lowShelf != nil && !lowShelfFits { dropped += 1 }
        if highShelf != nil && !highShelfFits { dropped += 1 }

        var peaks = filters.filter { $0.kind == .peak }.sorted { $0.frequency < $1.frequency }
        if peaks.count > 7 {
            dropped += peaks.count - 7
            peaks = Array(peaks.sorted { abs($0.gain) > abs($1.gain) }.prefix(7))
                .sorted { $0.frequency < $1.frequency }
        }

        var bands: [RoomCorrectionBand] = []
        if lowShelfFits, let shelf = lowShelf {
            bands.append(band(shelf, type: 1))
        } else {
            bands.append(RoomCorrectionBand(frequency: 60, gain: 0, q: 0.7, type: 1))
        }

        let neutralFrequencies = [120.0, 250, 500, 1_000, 2_000, 4_000, 8_000]
        for index in 0..<7 {
            if index < peaks.count {
                bands.append(band(peaks[index], type: 0))
            } else {
                bands.append(RoomCorrectionBand(frequency: neutralFrequencies[index],
                                                gain: 0, q: 1, type: 0))
            }
        }

        if highShelfFits, let shelf = highShelf {
            bands.append(band(shelf, type: 1))
        } else {
            bands.append(RoomCorrectionBand(frequency: 10_000, gain: 0, q: 0.7, type: 1))
        }

        let maximum = bands.map(\.gain).max() ?? 0
        let preamp = clamp(-max(maximum, 0), -20, 0)
        return RoomEQFilterSet(bands: bands,
                               preamp: (preamp * 10).rounded() / 10,
                               gainDB: (gainDB * 10).rounded() / 10,
                               accepted: accepted,
                               dropped: dropped)
    }

    /// Фильтр движка в полосу Room EQ, с приведением к пределам TotalMix.
    private static func band(_ filter: Filter, type: Int) -> RoomCorrectionBand {
        RoomCorrectionBand(frequency: clamp(filter.frequency, 20, 20_000),
                           gain: clamp(filter.gain, -20, 6),
                           q: clamp(filter.q, 0.4, 9.9),
                           type: type)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
