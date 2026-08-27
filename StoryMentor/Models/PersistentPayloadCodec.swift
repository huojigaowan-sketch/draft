import Foundation
import OSLog

/// Centralizes persistence of Codable values stored inside SwiftData Data attributes.
///
/// Encoding failures preserve the last known-good payload. Decoding failures are
/// logged distinctly from an intentionally empty payload so schema drift never
/// silently turns valid stored data into a new empty value on the next write.
nonisolated enum PersistentPayloadCodec {
    private static let logger = Logger(
        subsystem: "com.liuyicheng.StoryMentor",
        category: "PersistentPayload"
    )

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        default defaultValue: @autoclosure () -> Value,
        label: String
    ) -> Value {
        guard !data.isEmpty else { return defaultValue() }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error(
                "Unable to decode \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return defaultValue()
        }
    }

    static func decodeOptional<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        label: String
    ) -> Value? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error(
                "Unable to decode \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func decodeRequired<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        label: String
    ) throws -> Value {
        guard !data.isEmpty else {
            throw PersistentPayloadError.empty(label)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error(
                "Unable to decode \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw PersistentPayloadError.corrupted(label, underlying: error)
        }
    }

    static func encode<Value: Encodable>(
        _ value: Value,
        preserving previousData: Data,
        label: String
    ) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            logger.fault(
                "Unable to encode \(label, privacy: .public); preserving previous payload: \(error.localizedDescription, privacy: .public)"
            )
            return previousData
        }
    }
}

nonisolated enum PersistentPayloadError: LocalizedError {
    case empty(String)
    case corrupted(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .empty(let label):
            return "\(label) 尚未初始化。"
        case .corrupted(let label, let underlying):
            return "\(label) 无法读取：\(underlying.localizedDescription)"
        }
    }
}
