import Foundation
import Clairvoyant

struct CustomTypeHandle {

    /**
     A closure for type-erased storage of value data received from the server.
     - Parameter values: The encoded values received from the server
     - Parameter id: The id of the metric
     - Parameter storage: The local metric storage where the values should be inserted
     - Parameter decoder: The decoder to convert the values from data to their type
     - Returns: The newest decoded value
     */
    private let decodeAndStore: (_ values: [Timestamped<Data>], _ id: MetricId, _ storage: MetricStorage, _ decoder: AnyBinaryDecoder) throws -> AnyTimestamped?

    private let decodeLastValue: (Timestamped<Data>, AnyBinaryDecoder) throws -> AnyTimestamped

    private let createMetric: (MetricInfo, MetricStorage) throws -> Void

    init<T>(type: T.Type) where T: MetricValue {
        self.decodeAndStore = { data, id, storage, decoder in
            let values = try data.mapValues { try decoder.decode(T.self, from: $0) }
            try storage.store(values, for: id)
            return values.last
        }
        self.createMetric = { info, storage in
            _ = try storage.metric(info: info, type: T.self)
        }
        self.decodeLastValue = { data, decoder in
            try data.mapValue { try decoder.decode(T.self, from: $0) }
        }
    }

    func create(metric: MetricInfo, in storage: MetricStorage) throws {
        try createMetric(metric, storage)
    }

    func decode(_ data: [Timestamped<Data>], for id: MetricId, using decoder: AnyBinaryDecoder, andStoreIn storage: MetricStorage) throws -> AnyTimestamped? {
        try decodeAndStore(data, id, storage, decoder)
    }

    func decode(lastValue value: Timestamped<Data>, using decoder: AnyBinaryDecoder) throws -> AnyTimestamped {
        try decodeLastValue(value, decoder)
    }
}
