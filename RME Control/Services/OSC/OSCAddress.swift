import Foundation

/// OSC-адреса и суффиксы протокола TotalMix FX, которые использует приложение.
enum OSCAddress {
    /// Запрос полного состояния у TotalMix.
    static let requestAll = "/sendall"
    /// Имя подключённого устройства (строка).
    static let deviceStatus = "/status/device"
    /// Признак, что аудиоинтерфейс подключён (1/0).
    static let connectionStatus = "/status/connection"
    /// Префикс адреса уровня входа: `/level/in/<номер>`.
    static let levelInputPrefix = "/level/in/"
    /// Префикс адреса уровня выхода: `/level/out/<номер>`.
    static let levelOutputPrefix = "/level/out/"

    /// Суффиксы, добавляемые к адресу канала (`/output/0` + `/mute`).
    enum Suffix {
        static let fader = "/fader"
        static let faderLinear = "/faderlin"
        static let mute = "/mute"
        static let volume = "/volume"
        static let phantom = "/48v"
        static let instrument = "/instrument"
    }

    /// Секция Dynamics (компрессор) в Global OSC: `/input/8` + `/dynamics/enable`.
    enum Dynamics {
        static let enable = "/dynamics/enable"
        static let gain = "/dynamics/gain"
        static let attack = "/dynamics/attack"
        static let release = "/dynamics/release"
        static let threshold = "/dynamics/compthres"
        static let ratio = "/dynamics/compratio"
    }

    /// Секция EQ и Low Cut в Global OSC: `/input/8` + `/eq/band1gain`.
    enum EQ {
        static let enable = "/eq/enable"
        static let band1Type = "/eq/band1type"
        static let band1Gain = "/eq/band1gain"
        static let band1Freq = "/eq/band1freq"
        static let band1Q = "/eq/band1q"
        static let band2Gain = "/eq/band2gain"
        static let band2Freq = "/eq/band2freq"
        static let band2Q = "/eq/band2q"
        static let band3Type = "/eq/band3type"
        static let band3Gain = "/eq/band3gain"
        static let band3Freq = "/eq/band3freq"
        static let band3Q = "/eq/band3q"
        static let lowCutEnable = "/lowcut/enable"
        static let lowCutSlope = "/lowcut/slope"
        static let lowCutFreq = "/lowcut/freq"
    }

    /// Адреса кнопок Control Room по умолчанию.
    enum Defaults {
        static let speakerB = "/controlroom/speakerb"
        static let dim = "/controlroom/dim"
        static let mono = "/controlroom/mainmono"
    }

    /// Адреса кнопок из старых версий приложения — при загрузке заменяются на `Defaults`.
    enum Legacy {
        static let speakerB = "/1/mainSpeakerB"
        static let dim = "/1/mainDim"
        static let mono = "/1/mainMono"
    }

    static func output(_ channel: Int) -> String { "/output/\(channel)" }
    static func input(_ channel: Int) -> String { "/input/\(channel)" }

    /// Адрес посыла из входа в выход: `/mix/in/<вход>/<выход>`.
    static func send(inputAddress: String, outputAddress: String) -> String? {
        guard let input = channelNumber(in: inputAddress).flatMap(Int.init),
              let output = channelNumber(in: outputAddress).flatMap(Int.init) else {
            return nil
        }
        return "/mix/in/\(input)/\(output)"
    }

    /// Номер канала из OSC-адреса: последняя числовая сегмента
    /// (`/input/21` → `21`, `/input/21/eq` → `21`).
    static func channelNumber(in address: String) -> String? {
        address
            .split(separator: "/")
            .last(where: { Int($0) != nil })
            .map(String.init)
    }

    /// Адрес индикатора уровня, привязанный к номеру канала:
    /// `/input/21` → `/level/in/21`, `/output/8` → `/level/out/8`.
    static func levelAddress(forChannelAddress address: String, prefix: String) -> String {
        guard let number = channelNumber(in: address) else { return address }
        return prefix + number
    }

    /// Адрес для сравнения каналов: без пробелов и в нижнем регистре, чтобы
    /// `/input/8` и `/Input/8 ` считались одним и тем же каналом.
    static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
