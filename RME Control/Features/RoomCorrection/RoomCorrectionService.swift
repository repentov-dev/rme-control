import Foundation

/// Прогресс замера: позиция, канал и доля выполнения.
struct RoomCorrectionProgress: Sendable {
    var position: Int
    var totalPositions: Int
    var label: String
    var fraction: Double
}

/// Измеряет позиции и считает коррекции. Ничего не знает о UI.
@MainActor
final class RoomCorrectionService {
    private let engine = RoomAudioEngine()

    func measurePosition(index: Int,
                         total: Int,
                         device: RoomAudioDevice,
                         inputChannel: Int,
                         leftOutputChannel: Int,
                         rightOutputChannel: Int,
                         calibrationPath: String?,
                         progress: @escaping @MainActor (RoomCorrectionProgress) -> Void) async throws -> RoomPositionMeasurement {
        try Task.checkCancellation()
        let leftLabel = String(localized: "Left")
        let rightLabel = String(localized: "Right")
        progress(RoomCorrectionProgress(position: index, totalPositions: total,
                                        label: leftLabel, fraction: 0))
        let leftCurves = try await SotfCaptureCLI.capture(
            device: device,
            inputChannel: inputChannel,
            outputChannel: leftOutputChannel,
            calibrationPath: calibrationPath,
            repeats: RoomMeasurementAnalyzer.sweepsPerChannel
        ) { value in
            progress(RoomCorrectionProgress(position: index, totalPositions: total,
                                            label: leftLabel, fraction: value * 0.48))
        }
        try Task.checkCancellation()

        progress(RoomCorrectionProgress(position: index, totalPositions: total,
                                        label: rightLabel, fraction: 0.5))
        let rightCurves = try await SotfCaptureCLI.capture(
            device: device,
            inputChannel: inputChannel,
            outputChannel: rightOutputChannel,
            calibrationPath: calibrationPath,
            repeats: RoomMeasurementAnalyzer.sweepsPerChannel
        ) { value in
            progress(RoomCorrectionProgress(position: index, totalPositions: total,
                                            label: rightLabel, fraction: 0.5 + value * 0.48))
        }
        try Task.checkCancellation()

        guard let left = leftCurves.first, let right = rightCurves.first else {
            throw SotfCaptureError.badResponse
        }
        return RoomPositionMeasurement(
            index: index,
            left: left.points,
            right: right.points,
            leftCurves: leftCurves,
            rightCurves: rightCurves,
            sampleRate: 48_000
        )
    }

    func inputLevel(device: RoomAudioDevice, inputChannel: Int) async throws -> Double {
        try await engine.inputLevel(device: device, inputChannel: inputChannel)
    }

    func playTone(device: RoomAudioDevice, outputChannel: Int) async throws {
        try await engine.playTest(device: device, outputChannel: outputChannel, seconds: 0.8)
    }

    /// Считает L, R и общую стерео-коррекцию настоящим roomeq CLI.
    func corrections(positions: [RoomPositionMeasurement],
                     target: RoomCorrectionTarget,
                     dimensions: RoomDimensions?,
                     seed: Int) async throws -> [RoomCorrectionChannel: RoomCorrection] {
        guard !positions.isEmpty else { return [:] }
        // Показываем ту же кривую, что получил движок: среднее по всем точкам,
        // а не первую позицию.
        let left = RoomMeasurementAnalyzer.average(positions.map(\.left))
        let right = RoomMeasurementAnalyzer.average(positions.map(\.right))
        let stereo = RoomMeasurementAnalyzer.average(
            positions.map { RoomMeasurementAnalyzer.combined($0.left, $0.right) }
        )

        let leftCurves = positions.flatMap { position in
            position.leftCurves.isEmpty
                ? [RoomMeasurementCurve(points: position.left)]
                : position.leftCurves
        }
        let rightCurves = positions.flatMap { position in
            position.rightCurves.isEmpty
                ? [RoomMeasurementCurve(points: position.right)]
                : position.rightCurves
        }
        let stereoCurves = positions.map {
            RoomMeasurementCurve(points: RoomMeasurementAnalyzer.combined($0.left, $0.right))
        }
        let sampleRate = positions[0].sampleRate
        async let pairTask = RoomEQCLI.optimizePair(left: leftCurves,
                                                    right: rightCurves,
                                                    tilt: target.tiltDBPerOctave,
                                                    sampleRate: sampleRate,
                                                    dimensions: dimensions,
                                                    seed: seed,
                                                    positionCount: positions.count)
        async let monoTask = RoomEQCLI.optimizeSingle(measurements: stereoCurves,
                                                      tilt: target.tiltDBPerOctave,
                                                      sampleRate: sampleRate,
                                                      dimensions: dimensions,
                                                      seed: seed,
                                                      positionCount: positions.count)
        let (pair, mono) = try await (pairTask, monoTask)

        func correction(_ set: RoomEQFilterSet,
                        measured: [RoomResponsePoint],
                        channel: RoomCorrectionChannel) -> RoomCorrection {
            let predicted = RoomEQCLI.predicted(measured: measured, bands: set.bands)
            let residual = predicted.isEmpty ? 0 : sqrt(predicted.reduce(0) { $0 + $1.db * $1.db }
                                                        / Double(predicted.count))
            return RoomCorrection(channel: channel,
                                  bands: set.bands,
                                  preamp: set.gainDB,
                                  measured: measured,
                                  predicted: predicted,
                                  residualRMS: residual,
                                  engineAccepted: set.accepted,
                                  droppedFilters: set.dropped)
        }

        return [
            .left: correction(pair.left, measured: left, channel: .left),
            .right: correction(pair.right, measured: right, channel: .right),
            .stereo: correction(mono, measured: stereo, channel: .stereo)
        ]
    }


}
