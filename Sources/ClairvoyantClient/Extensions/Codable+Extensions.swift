import Foundation

extension UnkeyedDecodingContainer {
    
    @inline(__always)
    mutating func decode<T>() throws -> T where T : Decodable {
        try decode(T.self)
    }

    @inline(__always)
    mutating func decodeIfPresent<T>() throws -> T? where T : Decodable {
        try decodeIfPresent(T.self)
    }
}

extension KeyedDecodingContainer {

    @inline(__always)
    func decodeIfPresent<T>(forKey key: KeyedDecodingContainer<K>.Key) throws -> T? where T : Decodable {
        try decode(T.self, forKey: key)
    }

    func decode<T>(forKey key: KeyedDecodingContainer<K>.Key, or defaultValue: T) throws -> T where T : Decodable {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue
    }
}

extension UnkeyedEncodingContainer {

    mutating func encodeIfPresent<T>(_ value: T?) throws where T : Encodable {
        if let value {
            try encode(value)
        }
    }
}
