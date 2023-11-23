import Foundation
import Clairvoyant

public protocol GenericConsumableMetric {

    /// The consumer associated with the metric
    var consumer: MetricConsumer { get }

    /// The info of the metric
    var info: MetricInfo { get }

    /**
     Get the encoded data of the last value.
     - Returns: The encoded data of the timestamped last value, or `nil`
     */
    func lastValueData() async throws -> Data?

    /**
     Get a textual description of the last value.
     - Returns: A description of the timestamped last value, or `nil`
     */
    func lastValueDescription() async throws -> Timestamped<String>?

    /**
     Get the timestamped last value as a specific type.
     - Parameter type: The type to decode the last value data
     - Note: If the type does not match the underlying data, then an error will be thrown
     */
    func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R: MetricValue

    /**
     Get the history of the metric value in a specified range
     - Parameter start: The start date of the history to get
     - Parameter end: The end date of the history request
     - Parameter limit: The maximum number of entries to get, starting from `range.lowerBound`
     - Returns: The timestamped values within the range.
     - Throws: `MetricError`
     */
    func history<R>(from start: Date, to end: Date, limit: Int?, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue

    func historyDescription(from start: Date, to end: Date, limit: Int?) async throws -> [Timestamped<String>]
}

extension GenericConsumableMetric {

    /// The unique if of the metric
    public var id: MetricId {
        info.id
    }

    /// The data type of the values in the metric
    public var dataType: MetricType {
        info.dataType
    }

    /// A name to display for the metric
    public var name: String? {
        info.name
    }

    /**
     Describe the data of an encoded timestamped value.
     - Parameter data: The encoded data
     - Parameter type: The type of the encoded timestamped value
     - Returns: A timestamped textual description of the encoded value.
     */
    public func describe<T>(_ data: Data, as type: T.Type) -> Timestamped<String> where T: MetricValue {
        consumer.describe(data, as: type)
    }
    
    /**
     Get the history of the metric value in a specified range
     - Parameter range: The date interval for which to get the history
     - Parameter limit: The maximum number of entries to get, starting from `range.lowerBound`
     - Returns: The timestamped values within the range.
     - Throws: `MetricError`
     */
    public func history<R>(in range: ClosedRange<Date>, limit: Int?, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue {
        try await history(from: range.lowerBound, to: range.upperBound, limit: limit, as: type)
    }
    
    public func historyDescription(in range: ClosedRange<Date>, limit: Int?) async throws -> [Timestamped<String>] {
        try await historyDescription(from: range.lowerBound, to: range.upperBound, limit: limit)
    }
}
