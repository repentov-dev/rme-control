import Foundation

/// Кодирование и разбор OSC-пакетов. Чистые функции без состояния,
/// поэтому их легко покрывать тестами.
enum OSCCodec {
    struct Message: Sendable {
        let address: String
        let floatValue: Float?
        let stringValue: String?
    }

    /// Разбирает UDP-пакет. По спецификации OSC пакет содержит ровно одно сообщение
    /// или `#bundle`, элементы которого — вложенные пакеты.
    static func parsePacket(_ bytes: [UInt8]) -> [Message] {
        guard let (head, next) = readString(bytes, 0) else { return [] }
        guard head == "#bundle" else {
            return parseMessage(bytes, 0).map { [$0] } ?? []
        }

        // После "#bundle" идёт 8-байтовая метка времени, затем элементы: [размер Int32][пакет].
        var result: [Message] = []
        var elemStart = next + 8
        while elemStart + 4 <= bytes.count {
            let size = Int(bytes[elemStart]) << 24
                | Int(bytes[elemStart + 1]) << 16
                | Int(bytes[elemStart + 2]) << 8
                | Int(bytes[elemStart + 3])
            guard size > 0, size <= bytes.count - (elemStart + 4) else { break }
            result += parsePacket(Array(bytes[(elemStart + 4)..<(elemStart + 4 + size)]))
            elemStart += 4 + size
        }
        return result
    }

    /// Разбирает одно сообщение, начинающееся с `start`. Поддерживаются аргументы `,f` и `,s`;
    /// для других типов возвращается сообщение без значений.
    static func parseMessage(_ bytes: [UInt8], _ start: Int) -> Message? {
        guard let (address, next) = readString(bytes, start), address.hasPrefix("/") else { return nil }
        guard let (typeTags, offset) = readString(bytes, next) else { return nil }

        if typeTags.hasPrefix(",f"), offset + 4 <= bytes.count {
            let bits = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            return Message(address: address, floatValue: Float(bitPattern: bits), stringValue: nil)
        } else if typeTags.hasPrefix(",s"), let (str, _) = readString(bytes, offset) {
            return Message(address: address, floatValue: nil, stringValue: str)
        }
        return Message(address: address, floatValue: nil, stringValue: nil)
    }

    /// Кодирует сообщение с одним float-аргументом.
    static func encode(address: String, value: Float) -> Data {
        var data = Data()
        data.append(contentsOf: padded(address))
        data.append(contentsOf: padded(",f"))
        var bits = value.bitPattern.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &bits) { Array($0) })
        return data
    }

    /// Строка с завершающим нулём, выровненная до 4 байт.
    static func padded(_ s: String) -> [UInt8] {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    private static func readString(_ bytes: [UInt8], _ at: Int) -> (String, Int)? {
        guard at < bytes.count else { return nil }
        var i = at
        while i < bytes.count && bytes[i] != 0 { i += 1 }
        let str = String(bytes: bytes[at..<i], encoding: .utf8) ?? ""
        let end = at + ((i - at) / 4 + 1) * 4
        return (str, end)
    }
}
