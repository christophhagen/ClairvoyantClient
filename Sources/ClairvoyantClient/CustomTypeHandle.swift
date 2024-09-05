import Foundation
import Clairvoyant

public struct CustomTypeCollection {

    let customTypes: [MetricType : CustomTypeHandle]

    public init() {
        self.customTypes = [:]
    }

    public init(_ closure: (inout Builder) -> Void) {
        var builder = Builder()
        closure(&builder)
        builder.addWellKnownTypes()
        self.customTypes = builder.customTypes
    }

    public struct Builder {

        var customTypes: [MetricType : CustomTypeHandle] = [:]

        public mutating func add<T>(_ type: T.Type) where T: MetricValue {
            customTypes[type.valueType] = .init(type: type)
        }

        mutating func addWellKnownTypes() {
            add(Int.self)
            add(Double.self)
            add(Bool.self)
            add(String.self)
            add(Data.self)
            add(Date.self)
            add(ServerStatus.self)
            add(HTTPStatusCode.self)
            add(SemanticVersion.self)
        }
    }
}

struct CustomTypeHandle {

    private let decodeAndStore: ([Timestamped<Data>], MetricId, MetricStorage, AnyBinaryDecoder) throws -> Void

    private let createMetric: (MetricInfo, MetricStorage) throws -> Void

    init<T>(type: T.Type) where T: MetricValue {
        self.decodeAndStore = { data, id, storage, decoder in
            let values = try data.mapValues { try decoder.decode(T.self, from: $0) }
            try storage.store(values, for: id)
        }
        self.createMetric = { info, storage in
            _ = try storage.metric(info: info, type: T.self)
        }
    }

    func create(metric: MetricInfo, in storage: MetricStorage) throws {
        try createMetric(metric, storage)
    }

    func decode(_ data: [Timestamped<Data>], for id: MetricId, using decoder: AnyBinaryDecoder, andStoreIn storage: MetricStorage) throws {
        try decodeAndStore(data, id, storage, decoder)
    }
}
