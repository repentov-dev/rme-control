import Foundation

// JSON-контракт веб-пульта (`Resources/Web/remote.html`).
// Каналы в API адресуются индексом в списке настроек — так их видит страница.

/// Ответ `GET /api/state`.
struct WebStateDTO: Encodable {
    let connected: Bool
    let device: String
    let dim: Bool
    let mono: Bool
    let speakerB: Bool
    let settings: WebSettingsDTO
    let showDim: Bool
    let showMono: Bool
    let showSpeakerB: Bool
    let inputs: [WebInputDTO]
    let outputs: [WebOutputDTO]
    let sends: [WebSendDTO]
}

struct WebInputDTO: Encodable {
    let index: Int
    let name: String
    let has48v: Bool
    let hasInst: Bool
    let show: Bool
    let showInMain: Bool
    let hasCompressor: Bool
    let compressorOn: Bool
    let hasEQ: Bool
    let eqOn: Bool
    let phantom: Bool
    let instrument: Bool
}

struct WebOutputDTO: Encodable {
    let index: Int
    let name: String
    let show: Bool
    /// Положение фейдера 0…1.
    let value: Double
    /// Громкость в dB для подписи (по калибровочной кривой фейдера).
    let db: Double
    let muted: Bool
    let hasCompressor: Bool
    let compressorOn: Bool
    let hasEQ: Bool
    let eqOn: Bool
}

struct WebSendDTO: Encodable {
    let index: Int
    let name: String
    let show: Bool
    let value: Double
    let db: Double
    let muted: Bool
}

/// Что показывать на странице веб-пульта.
struct WebSettingsDTO: Codable {
    let buttons: Bool
    let inputs: Bool
    let levels: Bool
    let mute: Bool
}

/// Ответ `GET /api/levels`: уровни входов, выбранных для панели Levels.
struct WebLevelsDTO: Encodable {
    let levels: [Double]
    let names: [String]
}

/// Ответ на любое действие.
struct WebOKDTO: Encodable {
    var ok = true
}

// MARK: - Тела POST-запросов

/// `POST /api/volume`
struct WebVolumeRequest: Decodable {
    let index: Int
    let value: Double
}

/// `POST /api/mute`
struct WebMuteRequest: Decodable {
    let index: Int
    let muted: Bool
}

/// `POST /api/phantom`, `POST /api/instrument`
struct WebIndexRequest: Decodable {
    let index: Int
}

/// `POST /api/input-name`
struct WebInputNameRequest: Decodable {
    let index: Int
    let name: String
}

/// `POST /api/send-volume`
struct WebSendVolumeRequest: Decodable {
    let index: Int
    let value: Double
}

/// `POST /api/send-mute`
struct WebSendMuteRequest: Decodable {
    let index: Int
    let muted: Bool
}

/// `POST /api/settings` — меняются только переданные поля.
struct WebSettingsUpdateRequest: Decodable {
    let buttons: Bool?
    let inputs: Bool?
    let levels: Bool?
    let mute: Bool?
}

/// `POST /api/compressor`, `POST /api/eq`
struct WebPanelActionRequest: Decodable {
    let bus: String
    let index: Int
    let action: String
    let name: String?
    let value: Double?
    let enabled: Bool?
}

/// `GET /api/compressor`
struct WebCompressorStateDTO: Encodable {
    let name: String
    let isOutput: Bool
    let enabled: Bool
    let params: WebCompressorParamsDTO
    let level: Double
    let reduction: Double
    let output: Double
}

struct WebCompressorParamsDTO: Encodable {
    let threshold: Double
    let ratio: Double
    let attack: Double
    let release: Double
    let gain: Double
}

/// `GET /api/eq`
struct WebEQStateDTO: Encodable {
    let name: String
    let enabled: Bool
    let band1Type: Int
    let band1Gain: Double
    let band1Freq: Double
    let band1Q: Double
    let band2Gain: Double
    let band2Freq: Double
    let band2Q: Double
    let band3Type: Int
    let band3Gain: Double
    let band3Freq: Double
    let band3Q: Double
    let lowCutEnabled: Bool
    let lowCutSlope: Int
    let lowCutFreq: Double
}
