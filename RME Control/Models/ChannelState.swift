import Foundation

/// Регулируемый параметр компрессора канала (секция Dynamics в TotalMix).
/// Знает свой OSC-адрес (Global OSC) и допустимый диапазон значений.
enum CompressorParameter: String, CaseIterable, Identifiable {
    case threshold
    case ratio
    case attack
    case release
    case gain

    var id: String { rawValue }

    /// Суффикс адреса Global OSC: `/input/8` + `/dynamics/compthres`.
    var oscSuffix: String {
        switch self {
        case .threshold: return OSCAddress.Dynamics.threshold
        case .ratio: return OSCAddress.Dynamics.ratio
        case .attack: return OSCAddress.Dynamics.attack
        case .release: return OSCAddress.Dynamics.release
        case .gain: return OSCAddress.Dynamics.gain
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .threshold: return -60...0
        case .ratio: return 1...10
        case .attack: return 0...200
        case .release: return 100...999
        case .gain: return -30...30
        }
    }

    /// Подпись значения: у экспандера соотношение читается как 1:2.0.
    func formatted(_ value: Double, mode: DynamicsMode) -> String {
        if self == .ratio, mode == .expander {
            return String(format: "1:%.1f", value)
        }
        return formatted(value)
    }

    /// Нейтральное значение для активного режима (двойной клик по ручке).
    func neutral(for mode: DynamicsMode) -> Double {
        switch self {
        case .ratio: return 1
        case .threshold: return mode == .compressor ? 0 : -40
        default: return 0
        }
    }

    /// Порог и соотношение шлются в поля своего режима.
    func oscSuffix(for mode: DynamicsMode) -> String {
        switch self {
        case .threshold:
            return mode == .compressor ? OSCAddress.Dynamics.threshold : OSCAddress.Dynamics.expandThreshold
        case .ratio:
            return mode == .compressor ? OSCAddress.Dynamics.ratio : OSCAddress.Dynamics.expandRatio
        default:
            return oscSuffix
        }
    }

    /// Единица измерения для подписи (пусто у безразмерного ratio).
    var unit: String {
        switch self {
        case .attack, .release: return "ms"
        case .ratio: return ""
        default: return "dB"
        }
    }

    var title: String {
        switch self {
        case .threshold: return String(localized: "Threshold")
        case .ratio: return String(localized: "Ratio")
        case .attack: return String(localized: "Attack")
        case .release: return String(localized: "Release")
        case .gain: return String(localized: "Gain")
        }
    }

    /// Значение для подписи под ручкой: `2.5:1`, `120`, `+3.0`.
    func formatted(_ value: Double) -> String {
        switch self {
        case .ratio: return String(format: "%.1f:1", value)
        case .attack, .release: return "\(Int(value.rounded()))"
        default: return String(format: "%+.1f", value)
        }
    }
}

/// Какой прибор секции Dynamics работает в TotalMix. Порог и соотношение
/// у компрессора и экспандера свои, gain/attack/release — общие.
enum DynamicsMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case compressor
    case expander

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compressor: return String(localized: "Compressor")
        case .expander: return String(localized: "Expander")
        }
    }
}

/// Настройки секции Dynamics входного или выходного канала.
struct CompressorState: Codable, Equatable, Sendable {
    var enabled = false
    var mode: DynamicsMode = .compressor
    var gain: Double = 0            // make-up gain, dB (−30…+30)
    var attack: Double = 0          // мс (0…200)
    var release: Double = 200       // мс (100…999)
    var threshold: Double = 0       // компрессор, dB (−60…0)
    var ratio: Double = 1           // компрессор (1…10)
    var expandThreshold: Double = -40   // экспандер, dB (−60…0)
    var expandRatio: Double = 2         // экспандер (1…10)

    /// Порог и соотношение читаются у активного режима.
    func value(for parameter: CompressorParameter) -> Double {
        switch parameter {
        case .threshold: return mode == .compressor ? threshold : expandThreshold
        case .ratio: return mode == .compressor ? ratio : expandRatio
        case .attack: return attack
        case .release: return release
        case .gain: return gain
        }
    }

    mutating func set(_ parameter: CompressorParameter, value: Double) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        switch parameter {
        case .threshold:
            if mode == .compressor { threshold = clamped } else { expandThreshold = clamped }
        case .ratio:
            if mode == .compressor { ratio = clamped } else { expandRatio = clamped }
        case .attack: attack = clamped
        case .release: release = clamped
        case .gain: gain = clamped
        }
    }

    /// Кривая вход → выход в dB с учётом make-up. Компрессор загибает хвост
    /// вниз выше порога, экспандер — ниже порога.
    func transfer(_ db: Double) -> Double {
        guard enabled else { return db + gain }
        switch mode {
        case .compressor:
            guard ratio > 1, db > threshold else { return db + gain }
            return threshold + (db - threshold) / ratio + gain
        case .expander:
            guard expandRatio > 1, db < expandThreshold else { return db + gain }
            return expandThreshold + (db - expandThreshold) * expandRatio + gain
        }
    }

    /// Ослабление в dB при заданном уровне входа (dBFS) по статической кривой.
    /// TotalMix не отдаёт gain reduction по OSC — считаем сами.
    func gainReduction(forInputLevel level: Double) -> Double {
        guard enabled, level > -99 else { return 0 }
        let reduction: Double
        switch mode {
        case .compressor:
            guard ratio > 1, level > threshold else { return 0 }
            reduction = (level - threshold) * (1 - 1 / ratio)
        case .expander:
            guard expandRatio > 1, level < expandThreshold else { return 0 }
            reduction = (expandThreshold - level) * (expandRatio - 1)
        }
        // Оценка для индикатора: глубже 30 dB показывать нечего.
        return min(reduction, 30)
    }
}

/// Шина канала, к которому применяется EQ (TotalMix: Hardware Inputs / Outputs).
enum EQBus: Sendable {
    case input
    case output
}

/// Адресат EQ-панели: конкретный вход или выход.
struct EQTarget: Hashable, Sendable {
    let bus: EQBus
    let id: UUID
}

/// Адресат окна компрессора: конкретный вход или выход.
struct CompressorTarget: Hashable, Sendable {
    let bus: EQBus
    let id: UUID
}

/// Регулируемый параметр 3-полосного EQ и Low Cut (секция EQ в TotalMix).
/// Global OSC принимает «инженерные» значения: dB, Hz, Q и индекс списка.
enum EQParameter: String, CaseIterable, Identifiable, Sendable {
    case band1Type
    case band1Gain
    case band1Freq
    case band1Q
    case band2Gain
    case band2Freq
    case band2Q
    case band3Type
    case band3Gain
    case band3Freq
    case band3Q
    case lowCutSlope
    case lowCutFreq

    var id: String { rawValue }

    var oscSuffix: String {
        switch self {
        case .band1Type: return OSCAddress.EQ.band1Type
        case .band1Gain: return OSCAddress.EQ.band1Gain
        case .band1Freq: return OSCAddress.EQ.band1Freq
        case .band1Q: return OSCAddress.EQ.band1Q
        case .band2Gain: return OSCAddress.EQ.band2Gain
        case .band2Freq: return OSCAddress.EQ.band2Freq
        case .band2Q: return OSCAddress.EQ.band2Q
        case .band3Type: return OSCAddress.EQ.band3Type
        case .band3Gain: return OSCAddress.EQ.band3Gain
        case .band3Freq: return OSCAddress.EQ.band3Freq
        case .band3Q: return OSCAddress.EQ.band3Q
        case .lowCutSlope: return OSCAddress.EQ.lowCutSlope
        case .lowCutFreq: return OSCAddress.EQ.lowCutFreq
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .band1Gain, .band2Gain, .band3Gain: return -20...20
        case .band1Freq, .band2Freq, .band3Freq: return 20...20000
        case .lowCutFreq: return 20...500
        case .band1Q, .band2Q, .band3Q: return 0.4...9.9
        case .band1Type, .band3Type, .lowCutSlope: return 0...3
        }
    }

    /// Параметр-список (тип полосы, крутизна Low Cut) кодируется целым индексом.
    var isList: Bool {
        switch self {
        case .band1Type, .band3Type, .lowCutSlope: return true
        default: return false
        }
    }
}

/// Настройки 3-полосного EQ и Low Cut одного канала.
struct EQState: Codable, Equatable, Sendable {
    var enabled = false

    var band1Type = 1      // 0 Bell, 1 Low Shelf, 2 High-Pass, 3 Low Pass
    var band1Gain: Double = 0
    var band1Freq: Double = 100
    var band1Q: Double = 0.7

    var band2Gain: Double = 0
    var band2Freq: Double = 1000
    var band2Q: Double = 1

    var band3Type = 1      // 0 Bell, 1 High Shelf, 2 Low Pass, 3 High Pass
    var band3Gain: Double = 0
    var band3Freq: Double = 8000
    var band3Q: Double = 0.7

    var lowCutEnabled = false
    var lowCutSlope = 1    // индекс: 6, 12, 18, 24 dB/oct
    var lowCutFreq: Double = 80

    func value(for parameter: EQParameter) -> Double {
        switch parameter {
        case .band1Type: return Double(band1Type)
        case .band1Gain: return band1Gain
        case .band1Freq: return band1Freq
        case .band1Q: return band1Q
        case .band2Gain: return band2Gain
        case .band2Freq: return band2Freq
        case .band2Q: return band2Q
        case .band3Type: return Double(band3Type)
        case .band3Gain: return band3Gain
        case .band3Freq: return band3Freq
        case .band3Q: return band3Q
        case .lowCutSlope: return Double(lowCutSlope)
        case .lowCutFreq: return lowCutFreq
        }
    }

    mutating func set(_ parameter: EQParameter, value: Double) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let integer = Int(clamped.rounded())
        switch parameter {
        case .band1Type: band1Type = integer
        case .band1Gain: band1Gain = clamped
        case .band1Freq: band1Freq = clamped
        case .band1Q: band1Q = clamped
        case .band2Gain: band2Gain = clamped
        case .band2Freq: band2Freq = clamped
        case .band2Q: band2Q = clamped
        case .band3Type: band3Type = integer
        case .band3Gain: band3Gain = clamped
        case .band3Freq: band3Freq = clamped
        case .band3Q: band3Q = clamped
        case .lowCutSlope: lowCutSlope = integer
        case .lowCutFreq: lowCutFreq = clamped
        }
    }
}

/// Живое состояние выходного канала, полученное от TotalMix.
struct OutputState: Equatable, Sendable {
    /// Положение фейдера 0…1.
    var value: Double = 0.5
    var muted = false
    /// Громкость в dB, как её сообщил TotalMix (`/volume`).
    var db: Double = 0
    var eq = EQState()
    var compressor = CompressorState()
}

/// Живое состояние посыла: уровень фейдера, mute и dB.
struct SendState: Equatable, Sendable {
    var value: Double = FaderMath.position(forDB: 0)
    var muted = false
    var db: Double = 0
}

/// Живое состояние входного канала, полученное от TotalMix.
struct InputState: Equatable, Sendable {
    var phantom = false
    var instrument = false
    var compressor = CompressorState()
    var eq = EQState()
}
