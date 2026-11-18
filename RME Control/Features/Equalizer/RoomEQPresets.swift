import Foundation

/// Одна полоса пресета Room EQ: частота, усиление, добротность и тип кривой.
struct RoomEQPresetBand: Codable, Sendable, Equatable {
    let frequency: Double
    let gain: Double
    let q: Double
    let type: Int
}

/// Пресет наушников, приведённый к девяти полосам Room EQ.
struct RoomEQPreset: Identifiable, Sendable {
    let id: String
    let brand: String
    let model: String
    let source: String
    let preamp: Double
    let bands: [RoomEQPresetBand]

    /// Совпадает ли текущее состояние Room EQ с пресетом.
    func matches(_ state: RoomEQState) -> Bool {
        guard state.bands.count == bands.count else { return false }
        for (index, band) in bands.enumerated() {
            let current = state.bands[index]
            if abs(current.frequency - band.frequency) > 0.5
                || abs(current.gain - band.gain) > 0.05
                || abs(current.q - band.q) > 0.05
                || current.type != band.type {
                return false
            }
        }
        return true
    }
}

/// Бренд и его наушники для меню пресетов.
struct RoomEQPresetGroup: Identifiable, Sendable {
    let brand: String
    let presets: [RoomEQPreset]

    var id: String { brand }
}

/// Пресеты коррекции наушников для Room EQ.
///
/// Данные: AutoEQ (MIT), измерения oratory1990, Crinacle, Rtings и др.
/// Каждый пресет приведён к девяти полосам TotalMix Room EQ и нормализован
/// так, чтобы максимальное усиление было 0 dB (запас вместо предусиления).
enum RoomEQPresets {
    static let groups: [RoomEQPresetGroup] = [
        RoomEQPresetGroup(brand: "AKG", presets: [
            RoomEQPreset(
                id: "akg-k240-studio",
                brand: "AKG",
                model: "K240 Studio",
                source: "oratory1990",
                preamp: -7.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 75, gain: 2.9, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 204, gain: -3.2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1585, gain: 5.4, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 4207, gain: 5.2, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 5428, gain: 2.7, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 6459, gain: -2.3, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 9322, gain: -2, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 1.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k240-mkii",
                brand: "AKG",
                model: "K240 MKII",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 180, gain: -4, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 558, gain: 1.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 1605, gain: 4.7, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 2807, gain: -2.7, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 3488, gain: 2.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4180, gain: 5.6, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 6678, gain: -2.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 1.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k271-mkii",
                brand: "AKG",
                model: "K271 MKII",
                source: "oratory1990",
                preamp: -8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 145, gain: 6.6, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 650, gain: -2.9, q: 5.1, type: 0),
                    RoomEQPresetBand(frequency: 812, gain: -3.2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 830, gain: 3.3, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 1771, gain: -3.4, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 4439, gain: 8, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 8134, gain: -4.5, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 2.3, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k371",
                brand: "AKG",
                model: "K371",
                source: "oratory1990",
                preamp: -5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 67, gain: 3.1, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 182, gain: -2.3, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 1066, gain: -0.8, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 2048, gain: 0.5, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 4038, gain: 5, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 4232, gain: 0.9, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 5564, gain: -1.6, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 2.4, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k361",
                brand: "AKG",
                model: "K361",
                source: "oratory1990",
                preamp: -5.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 42, gain: -1.4, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 75, gain: 1.3, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 149, gain: -3.3, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 1338, gain: -1, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 2560, gain: -1, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 4019, gain: 5.9, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 7330, gain: 2.4, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k702",
                brand: "AKG",
                model: "K702",
                source: "oratory1990",
                preamp: -7.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 119, gain: -2.7, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 730, gain: 3.2, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 2241, gain: -3.5, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 2633, gain: -2, q: 5.3, type: 0),
                    RoomEQPresetBand(frequency: 3721, gain: 3.4, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 5483, gain: -4.7, q: 4.8, type: 0),
                    RoomEQPresetBand(frequency: 9459, gain: 3.2, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.7, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k712-pro",
                brand: "AKG",
                model: "K712 Pro",
                source: "Rtings",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 233, gain: -1.5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1927, gain: 5.6, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 2112, gain: -8.1, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 3057, gain: 1.2, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 3946, gain: -1.2, q: 5.4, type: 0),
                    RoomEQPresetBand(frequency: 5026, gain: 0.9, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 6777, gain: -3.9, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2.7, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "akg-k612-pro",
                brand: "AKG",
                model: "K612 Pro",
                source: "crinacle",
                preamp: -7.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 67, gain: -1.2, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 85, gain: 2.2, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 175, gain: -1.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 744, gain: 2.9, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 2519, gain: -2.4, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 4342, gain: 0.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5923, gain: -2.8, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 1.1, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Audeze", presets: [
            RoomEQPreset(
                id: "audeze-lcd-2",
                brand: "Audeze",
                model: "LCD-2",
                source: "oratory1990",
                preamp: -5.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 3.8, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 26, gain: 1.3, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 284, gain: -2.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 2076, gain: 2.8, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 2611, gain: -1.2, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 4093, gain: 5.8, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 5677, gain: -1.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8387, gain: 3.1, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audeze-lcd-x",
                brand: "Audeze",
                model: "LCD-X",
                source: "oratory1990",
                preamp: -6.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 108, gain: 0.6, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 121, gain: -3.4, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 771, gain: -2.3, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 1919, gain: 1.5, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 3763, gain: 6.7, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 5625, gain: -1.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8942, gain: 2, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audeze-lcd-xc",
                brand: "Audeze",
                model: "LCD-XC",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 60, gain: -4.2, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 416, gain: 1.8, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 1601, gain: -2.7, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 4062, gain: 4.4, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 4665, gain: 0.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5737, gain: -3.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 5, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -7.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audeze-lcd-5",
                brand: "Audeze",
                model: "LCD-5",
                source: "oratory1990",
                preamp: -7.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 121, gain: -2.1, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1241, gain: -5.3, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 2190, gain: 1.1, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 3769, gain: -8.3, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 4074, gain: 1.3, q: 4.8, type: 0),
                    RoomEQPresetBand(frequency: 4981, gain: -1.1, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 6732, gain: 7.7, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -6.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Audio-Technica", presets: [
            RoomEQPreset(
                id: "audio-technica-ath-m50x",
                brand: "Audio-Technica",
                model: "ATH-M50x",
                source: "oratory1990",
                preamp: -5.3,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 0.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 45, gain: -1.1, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 66, gain: 1.4, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 156, gain: -5.2, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 326, gain: 5.3, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 1640, gain: 0.9, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 3483, gain: 2.1, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 7077, gain: 2.8, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audio-technica-ath-m40x",
                brand: "Audio-Technica",
                model: "ATH-M40x",
                source: "oratory1990",
                preamp: -17.6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 17.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 48, gain: -16.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 348, gain: 6, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 1378, gain: -1.4, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 2225, gain: 0.8, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 2979, gain: 1.8, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 5150, gain: 3.3, q: 4.1, type: 0),
                    RoomEQPresetBand(frequency: 6306, gain: 1.6, q: 5.1, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -6.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audio-technica-ath-m70x",
                brand: "Audio-Technica",
                model: "ATH-M70x",
                source: "oratory1990",
                preamp: -4.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 3.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 69, gain: 1.3, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 110, gain: -2.1, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 681, gain: 3.6, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 2230, gain: -0.9, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 3133, gain: -0.9, q: 5.1, type: 0),
                    RoomEQPresetBand(frequency: 4327, gain: -3, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 6406, gain: 2, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.4, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audio-technica-ath-r70x",
                brand: "Audio-Technica",
                model: "ATH-R70x",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 34, gain: 0.7, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 58, gain: -0.6, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 93, gain: -4.4, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 2149, gain: -3.1, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 3519, gain: -3.2, q: 4.1, type: 0),
                    RoomEQPresetBand(frequency: 4308, gain: 4.8, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 4518, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.5, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "audio-technica-ath-ad700x",
                brand: "Audio-Technica",
                model: "ATH-AD700X",
                source: "oratory1990",
                preamp: -7.2,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 51, gain: 0.9, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 157, gain: -3.2, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 1422, gain: -4.8, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 2626, gain: 6.9, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 4063, gain: -2.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4990, gain: 3.5, q: 5.6, type: 0),
                    RoomEQPresetBand(frequency: 6954, gain: 5, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.2, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Austrian Audio", presets: [
            RoomEQPreset(
                id: "austrian-audio-hi-x55",
                brand: "Austrian Audio",
                model: "Hi-X55",
                source: "oratory1990",
                preamp: -7.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 1.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 53, gain: 2.7, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 138, gain: -7, q: 1.3, type: 0),
                    RoomEQPresetBand(frequency: 472, gain: 2.6, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 946, gain: -1.7, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 1284, gain: -7.8, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 2373, gain: 7.7, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 6612, gain: -1.8, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "austrian-audio-hi-x65",
                brand: "Austrian Audio",
                model: "Hi-X65",
                source: "oratory1990",
                preamp: -6.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 236, gain: -2.4, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 592, gain: -1.5, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 1659, gain: 6.9, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 2858, gain: -1.9, q: 5.4, type: 0),
                    RoomEQPresetBand(frequency: 3426, gain: 2.9, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 4145, gain: -1.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5982, gain: -4, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.5, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Beyerdynamic", presets: [
            RoomEQPreset(
                id: "beyerdynamic-dt-770-pro",
                brand: "Beyerdynamic",
                model: "DT 770 Pro",
                source: "oratory1990",
                preamp: -6.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 93, gain: 3.5, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 119, gain: -2.1, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 139, gain: -3.9, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 213, gain: 3.5, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 3684, gain: 6.8, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 6430, gain: -4.2, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 9561, gain: 2.3, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.4, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-880",
                brand: "Beyerdynamic",
                model: "DT 880",
                source: "oratory1990",
                preamp: -7.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 112, gain: -3.4, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 480, gain: 0.5, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 940, gain: -0.6, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 1320, gain: 2.1, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 2939, gain: -0.5, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 4480, gain: 3.9, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 5760, gain: -6.1, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-990-pro",
                brand: "Beyerdynamic",
                model: "DT 990 Pro",
                source: "oratory1990",
                preamp: -10.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 10.1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 64, gain: -7.4, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 541, gain: 3.1, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 4193, gain: 1.1, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 5897, gain: -4.8, q: 5.3, type: 0),
                    RoomEQPresetBand(frequency: 7136, gain: 3.1, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 7731, gain: -4.6, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 9436, gain: 2.7, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -9.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-1990-pro",
                brand: "Beyerdynamic",
                model: "DT 1990 Pro",
                source: "crinacle",
                preamp: -7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 121, gain: -2.3, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 612, gain: 1.3, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 2367, gain: 1.7, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 4448, gain: 3.9, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 6210, gain: 2.2, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 6950, gain: -2.6, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 8508, gain: -1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -6.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-1770-pro",
                brand: "Beyerdynamic",
                model: "DT 1770 Pro",
                source: "crinacle",
                preamp: -4.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 0.1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 70, gain: 2.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 135, gain: -4.6, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 236, gain: 4.3, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 521, gain: -1.5, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 2142, gain: 3.1, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 4208, gain: 4.8, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 8129, gain: -1.6, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 0.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-700-pro-x",
                brand: "Beyerdynamic",
                model: "DT 700 Pro X",
                source: "oratory1990",
                preamp: -6.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 62, gain: 1.5, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 131, gain: -4.1, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 265, gain: 4.2, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 2692, gain: -2.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 3557, gain: 6.8, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 4028, gain: 1.4, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 5709, gain: -2, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-dt-900-pro-x",
                brand: "Beyerdynamic",
                model: "DT 900 Pro X",
                source: "oratory1990",
                preamp: -5.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 82, gain: 0.7, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 94, gain: -2.3, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 2503, gain: -0.8, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 2966, gain: 1, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4103, gain: 3.8, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 6103, gain: -5.3, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 6339, gain: 1.5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "beyerdynamic-t1",
                brand: "Beyerdynamic",
                model: "T1",
                source: "oratory1990",
                preamp: -8.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 8.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 83, gain: -4.7, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1529, gain: 1.1, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 3596, gain: -1, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 4327, gain: 4.2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 4810, gain: 2.3, q: 5.5, type: 0),
                    RoomEQPresetBand(frequency: 6114, gain: -4.6, q: 5.4, type: 0),
                    RoomEQPresetBand(frequency: 8707, gain: -6.4, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.2, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Dan Clark Audio", presets: [
            RoomEQPreset(
                id: "dan-clark-audio-aeon-2-closed",
                brand: "Dan Clark Audio",
                model: "Aeon 2 Closed",
                source: "oratory1990",
                preamp: -6.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 0.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 110, gain: -3.6, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 379, gain: -2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1163, gain: -1.2, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 2113, gain: 1, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 3391, gain: 6.1, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 5811, gain: -2.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8927, gain: 2.8, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "dan-clark-audio-aeon-2-open",
                brand: "Dan Clark Audio",
                model: "Aeon 2 Open",
                source: "oratory1990",
                preamp: -4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 1.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 65, gain: 0.7, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 93, gain: -0.5, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 164, gain: -6, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 817, gain: -0.5, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 1582, gain: 2.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 4011, gain: 4, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 5726, gain: -5.3, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "dan-clark-audio-ether-2",
                brand: "Dan Clark Audio",
                model: "Ether 2",
                source: "oratory1990",
                preamp: -6.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 3.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 182, gain: -4, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 1115, gain: -2, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 2125, gain: 1.3, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 3856, gain: 6.2, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 6381, gain: -2.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 7485, gain: 2.1, q: 5.3, type: 0),
                    RoomEQPresetBand(frequency: 9013, gain: 6.4, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "dan-clark-audio-stealth",
                brand: "Dan Clark Audio",
                model: "Stealth",
                source: "oratory1990",
                preamp: -1.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 58, gain: 1.4, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 115, gain: -0.9, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 179, gain: 0.8, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 261, gain: -0.4, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 966, gain: -1.1, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 4046, gain: 1, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 5296, gain: -1.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 0.4, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Denon", presets: [
            RoomEQPreset(
                id: "denon-ah-d5200",
                brand: "Denon",
                model: "AH-D5200",
                source: "oratory1990",
                preamp: -5.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 86, gain: -4.7, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 405, gain: 3.6, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 1225, gain: 2, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 2317, gain: 3.1, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 5418, gain: -4, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 6714, gain: 2.2, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 8914, gain: 2.5, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "denon-ah-d7200",
                brand: "Denon",
                model: "AH-D7200",
                source: "oratory1990",
                preamp: -6.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 154, gain: -2.3, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 375, gain: 1, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 911, gain: -3.8, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 2165, gain: 6.5, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 3880, gain: 2.7, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 5545, gain: -5.1, q: 5.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 4.9, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.9, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "FiiO", presets: [
            RoomEQPreset(
                id: "fiio-ft1",
                brand: "FiiO",
                model: "FT1",
                source: "oratory1990",
                preamp: -4.6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 61, gain: 0.9, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 155, gain: -3.4, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 579, gain: 0.8, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 1735, gain: -1.9, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 3835, gain: 4.6, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 5303, gain: -5.6, q: 4.6, type: 0),
                    RoomEQPresetBand(frequency: 7882, gain: 4.5, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "fiio-ft1-pro",
                brand: "FiiO",
                model: "FT1 Pro",
                source: "oratory1990",
                preamp: -4.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 4.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 35, gain: -0.6, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 162, gain: -1.5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1818, gain: 4.7, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 2815, gain: -3.9, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 3839, gain: 1.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5731, gain: -2.5, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 9183, gain: 1.7, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.4, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Focal", presets: [
            RoomEQPreset(
                id: "focal-clear",
                brand: "Focal",
                model: "Clear",
                source: "oratory1990",
                preamp: -7.3,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 73, gain: -3.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1236, gain: -3.8, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 1563, gain: -0.9, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 2219, gain: 2, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 3136, gain: -1.1, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 4557, gain: 3.8, q: 4.1, type: 0),
                    RoomEQPresetBand(frequency: 8789, gain: 4.5, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "focal-clear-mg",
                brand: "Focal",
                model: "Clear Mg",
                source: "oratory1990",
                preamp: -6.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 94, gain: -4.2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1198, gain: -4, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 2223, gain: 1.7, q: 4.3, type: 0),
                    RoomEQPresetBand(frequency: 3196, gain: -1.7, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 4530, gain: 5.5, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 7343, gain: 1.5, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 8641, gain: 6.3, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.4, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "focal-utopia",
                brand: "Focal",
                model: "Utopia",
                source: "oratory1990",
                preamp: -8.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 8.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 68, gain: -5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1245, gain: -2.9, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 1946, gain: 3.4, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 3557, gain: 1.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5903, gain: -3.1, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 6765, gain: 2.6, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 8972, gain: 5.4, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "focal-elegia",
                brand: "Focal",
                model: "Elegia",
                source: "oratory1990",
                preamp: -6.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 2.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 156, gain: 1.5, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 267, gain: -1.8, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1159, gain: -2.1, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 2218, gain: 2, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 3780, gain: 6.4, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 5547, gain: -2.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 9158, gain: 4.8, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "focal-celestee",
                brand: "Focal",
                model: "Celestee",
                source: "oratory1990",
                preamp: -5.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -0.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 46, gain: 0.8, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 104, gain: -3.2, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 142, gain: -1, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 1200, gain: -2.5, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 2233, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4064, gain: 5.4, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 8300, gain: 3.6, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Fostex", presets: [
            RoomEQPreset(
                id: "fostex-t50rp-mk3",
                brand: "Fostex",
                model: "T50RP Mk3",
                source: "crinacle",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 71, gain: -5.6, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 241, gain: 1.7, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 289, gain: -1.5, q: 4.4, type: 0),
                    RoomEQPresetBand(frequency: 542, gain: 1.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 1001, gain: -3.1, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 2081, gain: 5.5, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 8580, gain: -4.3, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.5, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "HIFIMAN", presets: [
            RoomEQPreset(
                id: "hifiman-sundara",
                brand: "HIFIMAN",
                model: "Sundara",
                source: "oratory1990",
                preamp: -8.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 8.9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 56, gain: -4.5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 59, gain: -0.6, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 128, gain: 0.7, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 246, gain: -0.6, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 971, gain: -1.8, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 2115, gain: 2.1, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 8270, gain: 1.4, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "hifiman-ananda",
                brand: "HIFIMAN",
                model: "Ananda",
                source: "oratory1990",
                preamp: -6.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 67, gain: -0.5, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 116, gain: -2.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 945, gain: -2.1, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 1755, gain: 5, q: 1.3, type: 0),
                    RoomEQPresetBand(frequency: 3131, gain: -3.7, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 4472, gain: -0.7, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 5534, gain: 1.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.5, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "hifiman-arya",
                brand: "HIFIMAN",
                model: "Arya",
                source: "oratory1990",
                preamp: -6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 183, gain: -1.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 486, gain: -1.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 1729, gain: 5, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 2814, gain: -2.9, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 4688, gain: -3.3, q: 4.6, type: 0),
                    RoomEQPresetBand(frequency: 5750, gain: 1.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 6505, gain: -1.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "hifiman-edition-xs",
                brand: "HIFIMAN",
                model: "Edition XS",
                source: "oratory1990",
                preamp: -5.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.8, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 87, gain: -2.8, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 111, gain: 0.4, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 927, gain: -0.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 1420, gain: 1.3, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 1896, gain: 4, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 2896, gain: -3.7, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 5585, gain: 1.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "hifiman-he400se",
                brand: "HIFIMAN",
                model: "HE400se",
                source: "oratory1990",
                preamp: -7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 29, gain: 0.5, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 64, gain: -0.7, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 101, gain: -2.4, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 138, gain: 0.7, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 861, gain: -2.3, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 1619, gain: 1.1, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 1968, gain: 5.1, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2.6, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "KRK", presets: [
            RoomEQPreset(
                id: "krk-kns-8400",
                brand: "KRK",
                model: "KNS 8400",
                source: "Headphone.com Legacy",
                preamp: -10.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -1.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 67, gain: 10.8, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 104, gain: -8.6, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 197, gain: -5.7, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 438, gain: 6.5, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 602, gain: -1.5, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 1455, gain: 1.2, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 3452, gain: -4.3, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.1, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Meze", presets: [
            RoomEQPreset(
                id: "meze-99-classics",
                brand: "Meze",
                model: "99 Classics",
                source: "oratory1990",
                preamp: -15.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 232, gain: -20, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 320, gain: 15.7, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 379, gain: 2.1, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 1026, gain: 3.3, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 3754, gain: 11.5, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 4636, gain: -10.1, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 9590, gain: 2.3, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "meze-109-pro",
                brand: "Meze",
                model: "109 Pro",
                source: "oratory1990",
                preamp: -7.4,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 72, gain: -4.2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 83, gain: -1.2, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 825, gain: -0.9, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 2028, gain: 5.6, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 2856, gain: -1.9, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 4705, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8692, gain: 1.6, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.7, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "meze-empyrean",
                brand: "Meze",
                model: "Empyrean",
                source: "oratory1990",
                preamp: -6.3,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 87, gain: -4.8, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 202, gain: -0.7, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 902, gain: -0.9, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 1898, gain: 3.4, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 4533, gain: -1.5, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 6312, gain: 2.7, q: 4.4, type: 0),
                    RoomEQPresetBand(frequency: 7621, gain: 4.2, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -6.7, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "meze-elite",
                brand: "Meze",
                model: "Elite",
                source: "oratory1990",
                preamp: -5.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 4.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 72, gain: -1.9, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 244, gain: -4.6, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 329, gain: -0.9, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 429, gain: 1.9, q: 4.8, type: 0),
                    RoomEQPresetBand(frequency: 1055, gain: -1, q: 4.8, type: 0),
                    RoomEQPresetBand(frequency: 1858, gain: 5.5, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 8618, gain: 4.9, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.7, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Monoprice", presets: [
            RoomEQPreset(
                id: "monoprice-m1060",
                brand: "Monoprice",
                model: "M1060",
                source: "oratory1990",
                preamp: -7.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.8, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 67, gain: -3.7, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 231, gain: -1, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 394, gain: 1.6, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 3585, gain: 1.4, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 5158, gain: -3.1, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 6935, gain: 4.5, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 9146, gain: 7.8, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -5.4, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Neumann", presets: [
            RoomEQPreset(
                id: "neumann-ndh-20",
                brand: "Neumann",
                model: "NDH 20",
                source: "oratory1990",
                preamp: -6.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -2.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 83, gain: 1.2, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 194, gain: -3.7, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 797, gain: -0.8, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 1753, gain: 2.5, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 2307, gain: 6, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 3430, gain: -4.7, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 7033, gain: 2.7, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 3, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "neumann-ndh-30",
                brand: "Neumann",
                model: "NDH 30",
                source: "oratory1990",
                preamp: -6.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 3.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 53, gain: -0.8, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 66, gain: 0.6, q: 4.4, type: 0),
                    RoomEQPresetBand(frequency: 160, gain: -2.3, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1033, gain: -1.2, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 2262, gain: 3.5, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 3647, gain: -3.9, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 9234, gain: 6.1, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 0, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "OLLO", presets: [
            RoomEQPreset(
                id: "ollo-s4r",
                brand: "OLLO",
                model: "S4R",
                source: "oratory1990",
                preamp: -9.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 2.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 36, gain: 3.9, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 188, gain: -5.9, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 409, gain: 9.7, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 2060, gain: -3.3, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 3178, gain: 2.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 3962, gain: -2.9, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 7656, gain: 4.9, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.1, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Philips", presets: [
            RoomEQPreset(
                id: "philips-fidelio-x2hr",
                brand: "Philips",
                model: "Fidelio X2HR",
                source: "oratory1990",
                preamp: -7.8,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.8, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 29, gain: 1.2, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 64, gain: -7.1, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 261, gain: -1, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 1660, gain: -2.7, q: 4.6, type: 0),
                    RoomEQPresetBand(frequency: 2996, gain: 1.2, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4982, gain: 4.2, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 5096, gain: -8.2, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "philips-shp9500",
                brand: "Philips",
                model: "SHP9500",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 110, gain: -3, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 412, gain: 1, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 2130, gain: 3.7, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 3566, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4477, gain: -1.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5734, gain: -5.7, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 7370, gain: 2.1, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2.4, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Pioneer", presets: [
            RoomEQPreset(
                id: "pioneer-hdj-2000",
                brand: "Pioneer",
                model: "HDJ-2000",
                source: "Headphone.com Legacy",
                preamp: -12.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 12.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 74, gain: -11, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 131, gain: 1, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 520, gain: 2.1, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 1349, gain: -1.5, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 2558, gain: 6.1, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 3831, gain: -3.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 6895, gain: 6.6, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "RØDE", presets: [
            RoomEQPreset(
                id: "r-de-nth-100",
                brand: "RØDE",
                model: "NTH-100",
                source: "oratory1990",
                preamp: -13.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 13.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 52, gain: -10.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 198, gain: 1.1, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 411, gain: -1.4, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 1613, gain: 2.6, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 3013, gain: -1.2, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 5510, gain: -2.7, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 7684, gain: 4.2, q: 1.3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 2.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Samson", presets: [
            RoomEQPreset(
                id: "samson-sr850",
                brand: "Samson",
                model: "SR850",
                source: "Rtings",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 74, gain: -4.9, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 550, gain: 4.3, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 2846, gain: -3.1, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 4226, gain: 4.6, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 5787, gain: -5, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 8482, gain: -9.4, q: 1.5, type: 0),
                    RoomEQPresetBand(frequency: 8945, gain: 4.3, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -9.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Sennheiser", presets: [
            RoomEQPreset(
                id: "sennheiser-hd-600",
                brand: "Sennheiser",
                model: "HD 600",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 125, gain: -2.7, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 1298, gain: -1.2, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 2166, gain: 0.9, q: 3.3, type: 0),
                    RoomEQPresetBand(frequency: 3158, gain: -1.8, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 5433, gain: -1.2, q: 5.7, type: 0),
                    RoomEQPresetBand(frequency: 6639, gain: 2.2, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 8445, gain: 3.3, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-650",
                brand: "Sennheiser",
                model: "HD 650",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 37, gain: 0.7, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 118, gain: -3.1, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 1227, gain: -1.2, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 2055, gain: 1.2, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 3169, gain: -1.7, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 5332, gain: -1.1, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 8800, gain: 5.1, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-6xx",
                brand: "Sennheiser",
                model: "HD 6XX",
                source: "oratory1990",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 37, gain: 0.7, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 118, gain: -3.1, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 1227, gain: -1.2, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 2055, gain: 1.2, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 3169, gain: -1.7, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 5332, gain: -1.1, q: 5.8, type: 0),
                    RoomEQPresetBand(frequency: 8800, gain: 5.1, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-560s",
                brand: "Sennheiser",
                model: "HD 560S",
                source: "oratory1990",
                preamp: -9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 54, gain: -5.4, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 1148, gain: -1.5, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 1937, gain: 0.9, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 4502, gain: -1.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5639, gain: -0.9, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 7451, gain: 2, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 8983, gain: 4.4, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-660s2",
                brand: "Sennheiser",
                model: "HD 660S2",
                source: "oratory1990",
                preamp: -7.6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 7.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 98, gain: -3.5, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1206, gain: -2, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 2218, gain: 1.1, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 3206, gain: -1.2, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 4367, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5567, gain: -6.6, q: 3.9, type: 0),
                    RoomEQPresetBand(frequency: 8089, gain: 4.7, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-800-s",
                brand: "Sennheiser",
                model: "HD 800 S",
                source: "oratory1990",
                preamp: -7.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 142, gain: -2.3, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 1043, gain: -1, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 1445, gain: 1, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 1959, gain: 2.5, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 2640, gain: -0.9, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 3421, gain: 1.3, q: 5.5, type: 0),
                    RoomEQPresetBand(frequency: 5679, gain: -4.4, q: 4.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.3, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-280-pro",
                brand: "Sennheiser",
                model: "HD 280 Pro",
                source: "oratory1990",
                preamp: -5.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -4.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 41, gain: -3, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 77, gain: 4.7, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 101, gain: 2.7, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 126, gain: -3.7, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 178, gain: 2.3, q: 3.8, type: 0),
                    RoomEQPresetBand(frequency: 475, gain: -2.1, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 3946, gain: 5.9, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 3, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sennheiser-hd-25",
                brand: "Sennheiser",
                model: "HD 25",
                source: "Rtings",
                preamp: -7.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.7, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 56, gain: 0.8, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 91, gain: -1.1, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 176, gain: 0.8, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 235, gain: -4.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 597, gain: 5.8, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 5303, gain: 7.3, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 8484, gain: -6, q: 1.2, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 4.5, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Shure", presets: [
            RoomEQPreset(
                id: "shure-srh440",
                brand: "Shure",
                model: "SRH440",
                source: "oratory1990",
                preamp: -8.6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 8.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 63, gain: -6.6, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 219, gain: 3.2, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 678, gain: 0.8, q: 1.7, type: 0),
                    RoomEQPresetBand(frequency: 1746, gain: -1, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 3464, gain: 2.5, q: 1.9, type: 0),
                    RoomEQPresetBand(frequency: 6183, gain: 1.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8557, gain: -2.7, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.9, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "shure-srh840",
                brand: "Shure",
                model: "SRH840",
                source: "oratory1990",
                preamp: -6.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 58, gain: 2.4, q: 4.2, type: 0),
                    RoomEQPresetBand(frequency: 107, gain: -8.3, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 261, gain: 0.6, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 279, gain: 2.9, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 332, gain: -0.8, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 1946, gain: -0.7, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 5991, gain: -1.8, q: 2.6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "shure-srh840a",
                brand: "Shure",
                model: "SRH840A",
                source: "oratory1990",
                preamp: -3.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -1.4, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 121, gain: -3.6, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 170, gain: -0.7, q: 3.1, type: 0),
                    RoomEQPresetBand(frequency: 251, gain: 1.2, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 418, gain: -0.6, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 1254, gain: 2.3, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 4270, gain: 3.9, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 5403, gain: -3.1, q: 2.8, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -4.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "shure-srh1540",
                brand: "Shure",
                model: "SRH1540",
                source: "oratory1990",
                preamp: -2.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 1.9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 60, gain: 0.8, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 107, gain: -5.7, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 688, gain: 1.7, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 2709, gain: -2.3, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 4812, gain: 2, q: 4.7, type: 0),
                    RoomEQPresetBand(frequency: 5940, gain: -2.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 6484, gain: 2, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.4, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "shure-srh1840",
                brand: "Shure",
                model: "SRH1840",
                source: "oratory1990",
                preamp: -7.2,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 59, gain: 0.5, q: 2.9, type: 0),
                    RoomEQPresetBand(frequency: 180, gain: -1.2, q: 0.8, type: 0),
                    RoomEQPresetBand(frequency: 581, gain: 2, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 3060, gain: -4.5, q: 1.4, type: 0),
                    RoomEQPresetBand(frequency: 4732, gain: 4.2, q: 3.2, type: 0),
                    RoomEQPresetBand(frequency: 6333, gain: -1, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 7292, gain: 1.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.1, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Sony", presets: [
            RoomEQPreset(
                id: "sony-mdr-7506",
                brand: "Sony",
                model: "MDR-7506",
                source: "oratory1990",
                preamp: -10.3,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 10.3, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 48, gain: -9.5, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 230, gain: 3.7, q: 2.1, type: 0),
                    RoomEQPresetBand(frequency: 847, gain: 1.9, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 2916, gain: -1.9, q: 5.6, type: 0),
                    RoomEQPresetBand(frequency: 3748, gain: 2.6, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 4456, gain: -1.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5435, gain: -3.8, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 3.8, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sony-mdr-v6",
                brand: "Sony",
                model: "MDR-V6",
                source: "crinacle",
                preamp: -8.9,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 8.9, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 54, gain: -7.4, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 207, gain: 4.6, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 616, gain: 0.9, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 3513, gain: -1.8, q: 0.4, type: 0),
                    RoomEQPresetBand(frequency: 4672, gain: -1.6, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 8078, gain: -2.4, q: 3, type: 0),
                    RoomEQPresetBand(frequency: 9356, gain: -1.9, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 4.6, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sony-mdr-z1r",
                brand: "Sony",
                model: "MDR-Z1R",
                source: "oratory1990",
                preamp: -7.1,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -0.5, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 141, gain: -5.2, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 554, gain: 0.8, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 1407, gain: 0.9, q: 2.7, type: 0),
                    RoomEQPresetBand(frequency: 2152, gain: -0.7, q: 3.6, type: 0),
                    RoomEQPresetBand(frequency: 3295, gain: -8.7, q: 5, type: 0),
                    RoomEQPresetBand(frequency: 3946, gain: 7.1, q: 1.8, type: 0),
                    RoomEQPresetBand(frequency: 5822, gain: 3.1, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.1, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "sony-mdr-z7m2",
                brand: "Sony",
                model: "MDR-Z7M2",
                source: "oratory1990",
                preamp: -6.5,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: -1.1, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 59, gain: 2.2, q: 2.3, type: 0),
                    RoomEQPresetBand(frequency: 117, gain: -4.2, q: 0.7, type: 0),
                    RoomEQPresetBand(frequency: 1266, gain: 1.5, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 2558, gain: 3.2, q: 5.4, type: 0),
                    RoomEQPresetBand(frequency: 3308, gain: -3.3, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 4377, gain: 3.9, q: 4.9, type: 0),
                    RoomEQPresetBand(frequency: 5626, gain: -2.4, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: 3.9, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Superlux", presets: [
            RoomEQPreset(
                id: "superlux-hd-681",
                brand: "Superlux",
                model: "HD 681",
                source: "oratory1990",
                preamp: -7.6,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 5.8, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 174, gain: 1, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 496, gain: 2.4, q: 1, type: 0),
                    RoomEQPresetBand(frequency: 1105, gain: -1.8, q: 0.6, type: 0),
                    RoomEQPresetBand(frequency: 2458, gain: -1.4, q: 3.5, type: 0),
                    RoomEQPresetBand(frequency: 3826, gain: 3.2, q: 5.9, type: 0),
                    RoomEQPresetBand(frequency: 5194, gain: -6.1, q: 4.1, type: 0),
                    RoomEQPresetBand(frequency: 7758, gain: -2.3, q: 3.7, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -3.2, q: 0.7, type: 1),
                ]
            ),
            RoomEQPreset(
                id: "superlux-hd-668b",
                brand: "Superlux",
                model: "HD 668B",
                source: "oratory1990",
                preamp: -7.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 6.2, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 41, gain: 1.4, q: 1.6, type: 0),
                    RoomEQPresetBand(frequency: 84, gain: -4.5, q: 0.9, type: 0),
                    RoomEQPresetBand(frequency: 573, gain: 1.2, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 1417, gain: 1.5, q: 2.4, type: 0),
                    RoomEQPresetBand(frequency: 4513, gain: 4.9, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 5665, gain: -8.5, q: 4, type: 0),
                    RoomEQPresetBand(frequency: 7753, gain: -1.2, q: 4.4, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -0.3, q: 0.7, type: 1),
                ]
            ),
        ]),
        RoomEQPresetGroup(brand: "Yamaha", presets: [
            RoomEQPreset(
                id: "yamaha-hph-mt220",
                brand: "Yamaha",
                model: "HPH-MT220",
                source: "Innerfidelity",
                preamp: -6.7,
                bands: [
                    RoomEQPresetBand(frequency: 105, gain: 2.6, q: 0.7, type: 1),
                    RoomEQPresetBand(frequency: 54, gain: -4.4, q: 0.5, type: 0),
                    RoomEQPresetBand(frequency: 216, gain: -1.3, q: 3.4, type: 0),
                    RoomEQPresetBand(frequency: 354, gain: 1.3, q: 2.2, type: 0),
                    RoomEQPresetBand(frequency: 1019, gain: -4.8, q: 1.1, type: 0),
                    RoomEQPresetBand(frequency: 2345, gain: 6.7, q: 2, type: 0),
                    RoomEQPresetBand(frequency: 4313, gain: -1.5, q: 6, type: 0),
                    RoomEQPresetBand(frequency: 5956, gain: 5.3, q: 2.5, type: 0),
                    RoomEQPresetBand(frequency: 10000, gain: -1.7, q: 0.7, type: 1),
                ]
            ),
        ]),
    ]

    static let all: [RoomEQPreset] = groups.flatMap(\.presets)
}

