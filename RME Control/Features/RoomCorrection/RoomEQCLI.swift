import Foundation

/// Набор девяти полос, полученный от настоящего roomeq CLI.
struct RoomEQFilterSet: Sendable {
    var bands: [RoomCorrectionBand]
    var preamp: Double
    /// Усиление/калибровка, рассчитанные roomeq (gain-плагины).
    var gainDB: Double
    /// roomeq счёл коррекцию достаточно полезной и принял её.
    var accepted: Bool
}

enum RoomEQCLIError: LocalizedError {
    case binaryMissing
    case badMeasurement
    case failed(String)
    case noCorrection

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return String(localized: "The roomeq engine is missing from the app bundle. Rebuild the app.")
        case .badMeasurement:
            return String(localized: "The measurement is too short to calculate a correction.")
        case .failed(let message):
            return String(format: String(localized: "roomeq failed: %@"), message)
        case .noCorrection:
            return String(localized: "roomeq did not return a correction.")
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
                             dimensions: RoomDimensions?) async throws -> (left: RoomEQFilterSet, right: RoomEQFilterSet) {
        let holder = CancellableProcess()
        let work = Task(priority: .userInitiated) {
            try optimizePairSync(left: left, right: right, tilt: tilt,
                                 sampleRate: sampleRate, dimensions: dimensions,
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
                               dimensions: RoomDimensions?) async throws -> RoomEQFilterSet {
        let holder = CancellableProcess()
        let work = Task(priority: .userInitiated) {
            try optimizeSingleSync(measurements: measurements, tilt: tilt,
                                   sampleRate: sampleRate, dimensions: dimensions,
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

    private static func optimizePairSync(left: [RoomMeasurementCurve],
                                         right: [RoomMeasurementCurve],
                                         tilt: Double,
                                         sampleRate: Double,
                                         dimensions: RoomDimensions?,
                                         holder: CancellableProcess) throws -> (left: RoomEQFilterSet, right: RoomEQFilterSet) {
        guard left.allSatisfy({ $0.points.count > 8 }), right.allSatisfy({ $0.points.count > 8 }),
              !left.isEmpty, !right.isEmpty else { throw RoomEQCLIError.badMeasurement }
        let config = try makeConfig(
            speakers: ["left": left, "right": right],
            system: ["model": "stereo", "speakers": ["L": "left", "R": "right"]],
            tilt: tilt,
            sampleRate: sampleRate,
            dimensions: dimensions
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
                                           holder: CancellableProcess) throws -> RoomEQFilterSet {
        guard !measurements.isEmpty, measurements.allSatisfy({ $0.points.count > 8 }) else {
            throw RoomEQCLIError.badMeasurement
        }
        let config = try makeConfig(
            speakers: ["mono": measurements],
            system: nil,
            tilt: tilt,
            sampleRate: sampleRate,
            dimensions: dimensions
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
                                   dimensions: RoomDimensions?) throws -> [String: Any] {
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
                "min_freq": 20.0,
                "max_freq": 1_600.0,
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

        var recording: [String: Any] = [
            "recording_sample_rate": sampleRate,
            "signal_type": "Sweep",
            "signal_duration_secs": RoomMeasurementAnalyzer.sweepDuration,
            "sweep_start_freq": RoomMeasurementAnalyzer.sweepStart,
            "sweep_end_freq": RoomMeasurementAnalyzer.sweepEnd,
            "num_sweeps": 4,
            "pre_silence_s": 2.0,
            "signal_level_db": -6.02,
            "num_positions": speakers.values.map(\.count).max() ?? 1,
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
        let errorURL = directory.appendingPathComponent("stderr.log")
        let data = try JSONSerialization.data(withJSONObject: config, options: [])
        try data.write(to: configURL)
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--config", configURL.path,
                             "--output", outputURL.path,
                             "--sample-rate", String(sampleRate)]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(["RUST_LOG": "error"]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle
        holder.attach(process)
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()

        let log = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        guard fileManager.fileExists(atPath: outputURL.path) else {
            let tail = log.suffix(1200)
            throw RoomEQCLIError.failed(tail.isEmpty ? "exit \(process.terminationStatus)" : String(tail))
        }
        let outputData = try Data(contentsOf: outputURL)
        guard let output = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw RoomEQCLIError.noCorrection
        }
        return output
    }

    private static var binaryURL: URL? {
        if let url = Bundle.main.url(forResource: "roomeq", withExtension: nil) {
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
        let lowShelf = filters.first { $0.kind == .lowShelf }
        let highShelf = filters.first { $0.kind == .highShelf }
        var peaks = filters.filter { $0.kind == .peak }.sorted { $0.frequency < $1.frequency }
        if peaks.count > 7 {
            peaks = Array(peaks.sorted { abs($0.gain) > abs($1.gain) }.prefix(7))
                .sorted { $0.frequency < $1.frequency }
        }

        var bands: [RoomCorrectionBand] = []
        bands.append(RoomCorrectionBand(
            frequency: clamp(lowShelf?.frequency ?? 60, 20, 20_000),
            gain: clamp(lowShelf?.gain ?? 0, -20, 6),
            q: clamp(lowShelf?.q ?? 0.7, 0.4, 9.9),
            type: 1
        ))

        let neutralFrequencies = [120.0, 250, 500, 1_000, 2_000, 4_000, 8_000]
        for index in 0..<7 {
            if index < peaks.count {
                let peak = peaks[index]
                bands.append(RoomCorrectionBand(
                    frequency: clamp(peak.frequency, 20, 20_000),
                    gain: clamp(peak.gain, -20, 6),
                    q: clamp(peak.q, 0.4, 9.9),
                    type: 0
                ))
            } else {
                bands.append(RoomCorrectionBand(frequency: neutralFrequencies[index],
                                                gain: 0, q: 1, type: 0))
            }
        }

        bands.append(RoomCorrectionBand(
            frequency: clamp(highShelf?.frequency ?? 10_000, 20, 20_000),
            gain: clamp(highShelf?.gain ?? 0, -20, 6),
            q: clamp(highShelf?.q ?? 0.7, 0.4, 9.9),
            type: 1
        ))

        let maximum = bands.map(\.gain).max() ?? 0
        let preamp = clamp(-max(maximum, 0), -20, 0)
        return RoomEQFilterSet(bands: bands,
                               preamp: (preamp * 10).rounded() / 10,
                               gainDB: (gainDB * 10).rounded() / 10,
                               accepted: accepted)
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
