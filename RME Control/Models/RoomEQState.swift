import Foundation

/// Одна полоса Room EQ. У полос 1, 8 и 9 есть тип фильтра, у остальных — только
/// частота, усиление и добротность: так устроен Room EQ в TotalMix.
struct RoomEQBand: Codable, Equatable, Sendable {
    var frequency: Double
    var gain: Double = 0
    var q: Double
    var type: Int = 0

    /// Номера полос (с единицы), у которых TotalMix разрешает менять тип.
    static let typedBands: Set<Int> = [1, 8, 9]
}

/// Адресат окна Room EQ: выход, к которому оно относится, его парный канал
/// (в TotalMix это LEFT/RIGHT одной стереопары) и подпись для заголовка.
struct RoomEQTarget: Hashable, Sendable {
    /// Основной OSC-адрес выхода: `/output/0`.
    let address: String
    /// Парный адрес для второго канала: `/output/1`. `nil` — пары нет.
    let partner: String?
    /// Имя выхода для заголовка окна.
    let label: String
    /// Наушниковый выход: для него показываем пресеты коррекции наушников.
    var isHeadphone = false

    var hasPartner: Bool { partner != nil }
}

/// Какой канал стереопары правит окно Room EQ — аналог LEFT / link / RIGHT
/// в самом TotalMix.
enum RoomEQChannel: String, CaseIterable, Identifiable, Sendable {
    case left
    case both
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return String(localized: "Left")
        case .both: return String(localized: "Both")
        case .right: return String(localized: "Right")
        }
    }

    var isLinked: Bool { self == .both }
}

extension RoomEQTarget {
    /// Адреса, которые меняются при правке выбранного канала.
    func addresses(for channel: RoomEQChannel) -> [String] {
        switch channel {
        case .left: return [address]
        case .right: return partner.map { [$0] } ?? [address]
        case .both: return [address] + (partner.map { [$0] } ?? [])
        }
    }

    /// Адрес, чьё состояние показывает окно.
    func shownAddress(for channel: RoomEQChannel) -> String {
        channel == .right ? (partner ?? address) : address
    }
}

/// Регулируемый параметр Room EQ: значения уходят в TotalMix «инженерными»
/// величинами — dB, Гц, Q, миллисекунды и индексы списков.
enum RoomEQParameter: Hashable, Sendable {
    case bandGain(Int)
    case bandFrequency(Int)
    case bandQ(Int)
    case bandType(Int)
    case delay
    case crossfeed
    case volumeCalibration

    /// Суффикс Global OSC относительно адреса выхода.
    var oscSuffix: String {
        switch self {
        case .bandGain(let band): return "/roomeq/band\(band)gain"
        case .bandFrequency(let band): return "/roomeq/band\(band)freq"
        case .bandQ(let band): return "/roomeq/band\(band)q"
        case .bandType(let band): return "/roomeq/band\(band)type"
        case .delay: return OSCAddress.RoomEQ.delay
        case .crossfeed: return OSCAddress.RoomEQ.crossfeed
        case .volumeCalibration: return OSCAddress.RoomEQ.gain
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .bandGain: return -20...20
        case .bandFrequency: return 20...20000
        case .bandQ: return 0.4...9.9
        case .bandType: return 0...3
        case .delay: return 0...42.5
        case .crossfeed: return 0...5
        case .volumeCalibration: return -24...3
        }
    }

    /// Списочные параметры кодируются целым индексом.
    var isList: Bool {
        if case .bandType = self { return true }
        return false
    }

    var band: Int? {
        switch self {
        case .bandGain(let band), .bandFrequency(let band), .bandQ(let band), .bandType(let band):
            return band
        case .delay, .crossfeed, .volumeCalibration:
            return nil
        }
    }
}

/// Настройки Room EQ одного канала выхода: включение, задержка, crossfeed и
/// девять полос. Приходит из TotalMix по OSC, поэтому значения не сохраняются.
struct RoomEQState: Codable, Equatable, Sendable {
    var enabled = false
    /// Задержка в миллисекундах, 0…42.5.
    var delay: Double = 0
    /// Crossfeed, 0…5.
    var crossfeed: Double = 0
    /// Volume Calibration канала в dB — отдельный gain `/output/N/gain`, не фейдер.
    var volumeCalibration: Double = 0
    var bands: [RoomEQBand] = RoomEQState.factoryBands
    /// Полные полосы до применения Mix. Mix масштабирует только усиление.
    var baseBands: [RoomEQBand] = RoomEQState.factoryBands
    /// 0 — эквалайзер не действует, 1 — полное действие.
    var mix: Double = 1
    /// Vol.Cal до выключения Room EQ: возвращаем его при включении.
    var calibrationBeforeBypass: Double?

    /// Начальные положения полос — те же, что TotalMix выставляет сам.
    static let factoryBands: [RoomEQBand] = [
        RoomEQBand(frequency: 50, q: 0.7, type: 1),
        RoomEQBand(frequency: 100, q: 5),
        RoomEQBand(frequency: 150, q: 5),
        RoomEQBand(frequency: 200, q: 5),
        RoomEQBand(frequency: 250, q: 5),
        RoomEQBand(frequency: 300, q: 5),
        RoomEQBand(frequency: 400, q: 5),
        RoomEQBand(frequency: 600, q: 5, type: 0),
        RoomEQBand(frequency: 800, q: 0.7, type: 1)
    ]

    static let bandCount = 9

    /// Полоса по номеру с единицы; для неизвестного номера — нейтральная.
    func band(_ number: Int) -> RoomEQBand {
        guard bands.indices.contains(number - 1) else {
            return RoomEQBand(frequency: 1000, q: 1)
        }
        return bands[number - 1]
    }

    func value(for parameter: RoomEQParameter) -> Double {
        switch parameter {
        case .delay: return delay
        case .crossfeed: return crossfeed
        case .volumeCalibration: return volumeCalibration
        case .bandGain(let number): return band(number).gain
        case .bandFrequency(let number): return band(number).frequency
        case .bandQ(let number): return band(number).q
        case .bandType(let number): return Double(band(number).type)
        }
    }

    mutating func set(_ parameter: RoomEQParameter, value: Double) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let index: Int? = parameter.band.map { $0 - 1 }
        switch parameter {
        case .delay:
            delay = clamped
        case .crossfeed:
            // В TotalMix это не плавная величина, а положения Off и 1…5.
            crossfeed = clamped.rounded()
        case .volumeCalibration:
            volumeCalibration = clamped
        case .bandGain:
            guard let index, bands.indices.contains(index) else { return }
            bands[index].gain = clamped
            // На полном Mix внешнее значение становится новой базой.
            // При Mix < 1 это эхо собственных масштабированных полос:
            // базу не трогаем, иначе 100% не вернёт пресет один в один.
            if abs(mix - 1) < 0.01 {
                baseBands[index].gain = clamped
            }
        case .bandFrequency:
            guard let index, bands.indices.contains(index) else { return }
            bands[index].frequency = clamped
            baseBands[index].frequency = clamped
        case .bandQ:
            guard let index, bands.indices.contains(index) else { return }
            bands[index].q = clamped
            baseBands[index].q = clamped
        case .bandType:
            guard let index, bands.indices.contains(index) else { return }
            let type = Int(clamped.rounded())
            bands[index].type = type
            baseBands[index].type = type
        }
    }

    /// Правка усиления из приложения: при Mix < 1 сохраняет полный
    /// (немасштабированный) gain, чтобы 100% вернуло именно его.
    mutating func setBandGainFromUser(_ number: Int, value: Double) {
        guard bands.indices.contains(number - 1),
              baseBands.indices.contains(number - 1) else { return }
        let clamped = min(max(value, -20), 20)
        let index = number - 1
        bands[index].gain = clamped
        if mix > 0.001 {
            baseBands[index].gain = clamped / mix
        } else {
            baseBands[index].gain = clamped
        }
    }

    /// Ставит Mix: пересчитывает усиление всех полос от полного набора.
    mutating func setMix(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        guard baseBands.count == bands.count else { return }
        for index in bands.indices {
            bands[index].gain = baseBands[index].gain * clamped
        }
        mix = clamped
    }

    /// Полностью заменяет полосы (пресет, измерение) и сбрасывает Mix на 100%.
    mutating func applyBands(_ newBands: [RoomEQBand]) {
        guard newBands.count == RoomEQState.bandCount else { return }
        bands = newBands
        baseBands = newBands
        mix = 1
        calibrationBeforeBypass = nil
    }

    /// Нейтральное значение параметра — для сброса полосы двойным щелчком.
    static func neutral(for parameter: RoomEQParameter) -> Double {
        switch parameter {
        case .bandGain, .bandType: return 0
        case .bandFrequency: return 1000
        case .bandQ: return 1
        case .delay, .crossfeed, .volumeCalibration: return 0
        }
    }
}
