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

    /// Нейтральное значение (TotalMix не сжимает и ничего не добавляет).
    var neutral: Double { self == .ratio ? 1 : 0 }

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

/// Настройки компрессора входного канала и их влияние на уровень.
struct CompressorState: Equatable, Sendable {
    var enabled = false
    var gain: Double = 0       // make-up gain, dB (−30…+30)
    var attack: Double = 0     // мс (0…200)
    var release: Double = 200  // мс (100…999)
    var threshold: Double = 0  // dB (−60…0)
    var ratio: Double = 1      // (1…10)

    func value(for parameter: CompressorParameter) -> Double {
        switch parameter {
        case .threshold: return threshold
        case .ratio: return ratio
        case .attack: return attack
        case .release: return release
        case .gain: return gain
        }
    }

    mutating func set(_ parameter: CompressorParameter, value: Double) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        switch parameter {
        case .threshold: threshold = clamped
        case .ratio: ratio = clamped
        case .attack: attack = clamped
        case .release: release = clamped
        case .gain: gain = clamped
        }
    }

    /// Ослабление в dB при заданном уровне входа (dBFS) по статической кривой.
    /// TotalMix не отдаёт gain reduction по OSC — считаем сами.
    func gainReduction(forInputLevel level: Double) -> Double {
        guard enabled, ratio > 1, level > threshold else { return 0 }
        return (level - threshold) * (1 - 1 / ratio)
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
struct EQState: Equatable, Sendable {
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
