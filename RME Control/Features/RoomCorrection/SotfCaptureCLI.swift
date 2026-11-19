import Foundation

enum SotfCaptureError: LocalizedError {
    case binaryMissing
    case failed(String)
    case badResponse
    /// Движок записал звук, но не нашёл в нём свип.
    case noSignalLock
    /// Вход перегружен: форма свипа искажена, корреляция не находится.
    case clipped
    /// Устройство не удалось открыть или в нём нет нужных каналов.
    case deviceUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return String(localized: "A measurement engine is missing from this build.")
        case .failed:
            // Текст движка уходит в системный лог при показе ошибки (MeasurementFailure).
            return String(localized: "The measurement failed.")
        case .badResponse:
            return String(localized: "The engine returned no usable measurement.")
        case .noSignalLock:
            return String(localized: "Could not recognise the signal.")
        case .clipped:
            return String(localized: "The recording is clipped.")
        case .deviceUnavailable:
            return String(localized: "Could not open the audio device.")
        }
    }
}

/// Разделяемый запущенный процесс: отмена задачи завершает CLI,
/// чтобы после закрытия Measure не оставалось фоновой нагрузки.
final class CancellableProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

/// Тонкая оболочка над sotf-capture: запись и анализ делает он.
enum SotfCaptureCLI {
    static func capture(device: RoomAudioDevice,
                        inputChannel: Int,
                        outputChannel: Int,
                        calibrationPath: String?,
                        repeats: Int,
                        progress: @escaping @MainActor (Double) -> Void) async throws -> [RoomMeasurementCurve] {
        let holder = CancellableProcess()
        let work = Task(priority: .userInitiated) {
            var curves: [RoomMeasurementCurve] = []
            for index in 0..<max(repeats, 1) {
                try Task.checkCancellation()
                let curve = try captureOnce(device: device,
                                            inputChannel: inputChannel,
                                            outputChannel: outputChannel,
                                            calibrationPath: calibrationPath,
                                            name: "rme-\(outputChannel)-\(inputChannel)-\(index)",
                                            holder: holder)
                curves.append(curve)
                let fraction = Double(index + 1) / Double(max(repeats, 1))
                await MainActor.run { progress(fraction) }
            }
            return curves
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
            holder.terminate()
        }
    }

    private static func captureOnce(device: RoomAudioDevice,
                                    inputChannel: Int,
                                    outputChannel: Int,
                                    calibrationPath: String?,
                                    name: String,
                                    holder: CancellableProcess) throws -> RoomMeasurementCurve {
        guard let binary = binaryURL else { throw SotfCaptureError.binaryMissing }
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("rme-sotf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        var arguments = [
            "capture", "--signal", "sweep",
            "--duration", String(Int(RoomMeasurementAnalyzer.captureDuration)),
            "--sample-rate", "48000",
            "--channels", "1",
            "--hwaudio-send-to", "\(outputChannel)",
            "--hwaudio-record-from", "\(inputChannel)",
            "--input-device", device.name,
            "--output-device", device.name,
            "--output-dir", directory.path,
            "--name", name,
            "--start-freq", "20",
            "--end-freq", "20000",
            "--amp", "0.5",
            "--json"
        ]
        if let calibrationPath, !calibrationPath.isEmpty {
            arguments += ["--mic-calibration", "\(inputChannel)=\(calibrationPath)"]
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        holder.attach(process)
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let text = errorText.isEmpty ? "exit \(process.terminationStatus)" : errorText
            if text.contains("No reliable signal lock") {
                throw SotfCaptureError.noSignalLock
            }
            if text.contains("Recording clipped") || text.contains("clipped hard") {
                throw SotfCaptureError.clipped
            }
            if text.contains("identify playback device")
                || text.contains("identify microphone device")
                || text.contains("enumerate input devices")
                || text.contains("enumerate output devices")
                || text.contains("default input config")
                || text.contains("supported output configs") {
                throw SotfCaptureError.deviceUnavailable
            }
            throw SotfCaptureError.failed(text)
        }

        let jsonLine = output
            .split(separator: "\n")
            .last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") })
        guard let jsonLine,
              let data = jsonLine.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let csvPath = object["csv"] as? String else {
            throw SotfCaptureError.badResponse
        }
        return try parseCSV(URL(fileURLWithPath: csvPath))
    }

    private static func parseCSV(_ url: URL) throws -> RoomMeasurementCurve {
        let text = try String(contentsOf: url, encoding: .utf8)
        var frequencies: [Double] = []
        var values: [Double] = []
        for line in text.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 2,
                  let frequency = Double(columns[0]),
                  let value = Double(columns[1]),
                  frequency.isFinite, value.isFinite,
                  frequency > 0 else { continue }
            frequencies.append(frequency)
            values.append(value)
        }
        guard frequencies.count > 8 else { throw SotfCaptureError.badResponse }

        // Только для отображения: приводим уровень к середине. roomeq
        // нормализует сам; на коррекцию это не влияет.
        let mid = zip(frequencies, values)
            .filter { $0.0 >= 300 && $0.0 <= 3_000 }
            .map(\.1)
        let reference = mid.isEmpty ? 0 : mid.reduce(0, +) / Double(mid.count)
        let points = zip(frequencies, values).map {
            RoomResponsePoint(frequency: $0.0, db: $0.1 - reference)
        }
        return RoomMeasurementCurve(points: points)
    }

    private static var binaryURL: URL? {
        // Модуль замера может быть скачан отдельно — он важнее бандла.
        if let url = MeasurementModule.binary(named: "sotf-capture") {
            return url
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent("build/sotf-capture"),
            root.appendingPathComponent("RME Control/Resources/sotf-capture"),
            root.appendingPathComponent("vendor/sotf-capture")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
