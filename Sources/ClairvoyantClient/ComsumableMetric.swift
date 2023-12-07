import Foundation
import Clairvoyant

/**
 An object to access a specific metric from a server
 */
public actor ConsumableMetric<T> where T: MetricValue {

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
    public init(consumer: MetricConsumer, id: MetricId, name: String? = nil, description: String? = nil) {
        self.consumer = consumer
        self.info = .init(id: id, dataType: T.valueType, name: name, description: description)
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

    /**
     Get the last value of the metric from the server.
     - Returns: The timestamped last value of the metric, if one exists
     - Throws: `MetricError`
     */
    public func lastValue() async throws -> Timestamped<T>? {
        try await consumer.lastValue(for: id)
    }

    /**
     Get the history of the metric value in a specified range
     - Parameter range: The date interval for which to get the history
     - Parameter limit: The maximum number of entries to get, starting from `range.lowerBound`
     - Returns: The timestamped values within the range.
     - Throws: `MetricError`
     */
    public func history(in range: ClosedRange<Date> = Date.distantPast...Date.distantFuture, limit: Int? = nil) async throws -> [Timestamped<T>] {
        try await consumer.history(for: id, in: range, limit: limit)
    }
    
    /**
     Get the history of the metric value in a specified range
     - Parameter start: The start date of the history to get
     - Parameter end: The end date of the history request
     - Parameter limit: The maximum number of entries to get, starting from `start`
     - Returns: The timestamped values within the range, sorted from `start` to `end`
     - Note: It's possible for `end` to be before `start`. In this case, `limit` is still applied from the `start`, and the result is sorted in reverse (from `start` to `end`)
     - Throws: `MetricError`
     */
    public func history(from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) async throws -> [Timestamped<T>] {
        try await consumer.history(for: id, from: start, to: end, limit: limit)
    }
    
    public func decode(lastValueData: Data) throws -> Timestamped<T> {
        try consumer.decoder.decode(from: lastValueData)
    }
    
}

extension ConsumableMetric: GenericConsumableMetric {

    public func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R : MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        return try await consumer.lastValue(for: id, type: R.self)
    }

    public func history<R>(from start: Date, to end: Date, limit: Int? = nil, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        let values = try await self.history(from: start, to: end, limit: limit)
        return try values.map {
            guard let result = $0 as? Timestamped<R> else {
                throw MetricError.typeMismatch
            }
            return result
        }
    }

    public func lastValueData() async throws -> Data? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        return data
    }

    public func lastValueDescription() async throws -> Timestamped<String>? {
        guard let value = try await lastValue() else {
            return nil
        }
        return value.mapValue { "\($0)" }
    }

    public func historyDescription(from start: Date, to end: Date, limit: Int?) async throws -> [Timestamped<String>] {
        try await history(from: start, to: end, limit: limit)
            .map { $0.mapValue(String.init(describing:)) }
    }
}
