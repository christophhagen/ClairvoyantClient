import Foundation
import Clairvoyant

/**
 A consumable metric to handle unknown types.
 */
public actor UnknownConsumableMetric {

    /// The main consumer of the server
    public nonisolated let consumer: MetricConsumer

    /// The info of the metric
    public nonisolated let info: MetricInfo

    /// The unique if of the metric
    public nonisolated var id: MetricId {
        info.id
    }

    /**
     Create a handle for a metric.
     - Parameter consumer: The consumer of the server
     - Parameter id: The id of the metric
     - Parameter name: The optional name of the metric
     - Parameter description: A textual description of the metric
     */
    public init(consumer: MetricConsumer, id: MetricId, dataType: MetricType, name: String? = nil, description: String? = nil) {
        self.consumer = consumer
        self.info = .init(id: id, dataType: dataType, name: name, description: description)
    }
    
    /**
     Create a handle for a metric.
     - Parameter consumer: The consumer of the server
     - Parameter info: The info of the metric
     */
    public init(consumer: MetricConsumer, info: MetricInfo) {
        self.consumer = consumer
        self.info = info
    }

}

extension UnknownConsumableMetric: GenericConsumableMetric {
    
    public func lastValueData() async throws -> Data? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        return data
    }
    
    public func lastValueDescription() async throws -> Timestamped<String>? {
        guard let value = try await lastValueData() else {
            return nil
        }
        do {
            let decoded = try consumer.decoder.decode(AnyTimestamped.self, from: value)
            return .init(value: "\(value.count) bytes", timestamp: decoded.timestamp)
        } catch {
            throw MetricError.failedToDecode
        }
    }
    
    public func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R : MetricValue {
        guard info.dataType == R.valueType else {
            throw MetricError.typeMismatch
        }
        return try await consumer.lastValue(for: id, type: R.self)
    }
    
    public func history<R>(in range: ClosedRange<Date>, limit: Int?, as type: R.Type) async throws -> [Timestamped<R>] where R : MetricValue {
        try await consumer.history(for: id, in: range, limit: limit)
    }
    
    public func historyDescription(in range: ClosedRange<Date>, limit: Int?) async throws -> [Timestamped<String>] {
        let data = try await consumer.historyData(for: id, in: range, limit: limit)
        return try consumer.decoder.decode([AnyTimestamped].self, from: data)
            .map { Timestamped<String>.init(value: "Some data", timestamp: $0.timestamp) }
    }
}

/**
 An internal struct to partially decode abstract timestamped values
 */
struct AnyTimestamped: Decodable {

    let timestamp: Date

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.timestamp = try container.decode(Date.self)
    }
}
