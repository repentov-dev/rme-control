import Foundation

/// Отказ замера в двух строках: что случилось и что делать.
///
/// Движки (`sotf-capture`, `roomeq`) пишут технические формулировки и свои
/// имена — это уходит в системный лог. Пользователь видит короткий заголовок
/// крупным шрифтом по центру окна Measure и подсказку под ним.
struct MeasurementFailure: Equatable, Sendable {
    var title: String
    var hint: String?

    init(title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }
}

extension MeasurementFailure {
    /// Переводит ошибку движка в понятную пару строк. Ошибки без своего
    /// перевода (файл калибровки, настройки) приходят уже с текстом для человека.
    static func describing(_ error: Error) -> MeasurementFailure {
        if let error = error as? SotfCaptureError {
            return measurement(error)
        }
        if let error = error as? RoomEQCLIError {
            return correction(error)
        }
        if let error = error as? RoomAudioEngine.EngineError {
            return engine(error)
        }
        return MeasurementFailure(title: error.localizedDescription)
    }

    // MARK: - Подсказки

    private static var checkMeasurement: String {
        String(localized: "Check the microphone input and the gain, then measure again.")
    }

    /// Замер идёт только на 48 кГц. Пока интерфейс на другой частоте, запуск
    /// заблокирован: свип не сойдётся и движок вернёт ошибку.
    static func sampleRateMismatch(rate: Double?) -> MeasurementFailure {
        let title = String(localized: "Set the interface to 48 kHz before measuring. The measurement engine runs at 48 kHz.")
        guard let rate, rate > 0 else { return MeasurementFailure(title: title) }
        return MeasurementFailure(
            title: title,
            hint: String(format: String(localized: "Interface rate: %@"),
                         String(format: "%.1f kHz", rate / 1_000))
        )
    }

    // MARK: - Замер

    private static func measurement(_ error: SotfCaptureError) -> MeasurementFailure {
        switch error {
        case .binaryMissing:
            NSLog("sotf-capture: binary missing from the bundle")
            return MeasurementFailure(
                title: String(localized: "A measurement engine is missing from this build."),
                hint: String(localized: "Reinstall RME Control.")
            )
        case .failed(let message):
            NSLog("sotf-capture: %@", message)
            return MeasurementFailure(
                title: String(localized: "The measurement failed."),
                hint: checkMeasurement
            )
        case .badResponse:
            return MeasurementFailure(
                title: String(localized: "The engine returned no usable measurement."),
                hint: checkMeasurement
            )
        case .noSignalLock:
            return MeasurementFailure(
                title: String(localized: "Could not recognise the signal."),
                hint: checkMeasurement
            )
        case .clipped:
            return MeasurementFailure(
                title: String(localized: "The recording is clipped."),
                hint: String(localized: "Lower the microphone gain and measure again.")
            )
        case .deviceUnavailable:
            return MeasurementFailure(
                title: String(localized: "Could not open the audio device."),
                hint: String(localized: "Quit other audio apps, check the cable, then try again.")
            )
        }
    }

    // MARK: - Коррекция

    private static func correction(_ error: RoomEQCLIError) -> MeasurementFailure {
        switch error {
        case .binaryMissing:
            NSLog("roomeq: binary missing from the bundle")
            return MeasurementFailure(
                title: String(localized: "A measurement engine is missing from this build."),
                hint: String(localized: "Reinstall RME Control.")
            )
        case .badMeasurement:
            return MeasurementFailure(
                title: String(localized: "The measurement is too short."),
                hint: String(localized: "Run a full measurement before calculating a correction.")
            )
        case .failed(let message):
            NSLog("roomeq: %@", message)
            return MeasurementFailure(
                title: String(localized: "Could not calculate the correction."),
                hint: String(localized: "The engine rejected this measurement. Measure again, or reduce the target tilt.")
            )
        case .noCorrection:
            return MeasurementFailure(
                title: String(localized: "The engine returned no correction."),
                hint: String(localized: "Measure again. If it repeats, the room is already close to the target.")
            )
        }
    }

    /// Движок отказался записывать коррекцию: она ниже его порога.
    static var engineUnchanged: MeasurementFailure {
        MeasurementFailure(
            title: String(localized: "The engine found nothing to change."),
            hint: String(localized: "This correction is below the engine's threshold. Applying it would only overwrite the current Room EQ.")
        )
    }

    // MARK: - Звук

    private static func engine(_ error: RoomAudioEngine.EngineError) -> MeasurementFailure {
        switch error {
        case .noDevice:
            return MeasurementFailure(
                title: String(localized: "No RME audio device found."),
                hint: String(localized: "Connect the interface and reopen Measure.")
            )
        case .noInput:
            return MeasurementFailure(
                title: String(localized: "The selected microphone input is unavailable."),
                hint: String(localized: "Choose another channel in Measure.")
            )
        case .noOutput:
            return MeasurementFailure(
                title: String(localized: "The selected speaker output is unavailable."),
                hint: String(localized: "Choose another channel in Measure.")
            )
        case .engine(let message):
            NSLog("audio engine: %@", message)
            return MeasurementFailure(
                title: String(localized: "The audio engine stopped."),
                hint: String(localized: "Reopen Measure. If it repeats, restart RME Control.")
            )
        case .silent:
            return MeasurementFailure(
                title: String(localized: "No signal from the microphone. Check the input and level."),
                hint: checkMeasurement
            )
        case .tooShort:
            return MeasurementFailure(
                title: String(localized: "The recording is too short. Try again."),
                hint: nil
            )
        case .channelUnavailable:
            return MeasurementFailure(
                title: String(localized: "The interface does not expose this channel."),
                hint: String(localized: "Choose another channel or check the routing in TotalMix.")
            )
        }
    }
}
