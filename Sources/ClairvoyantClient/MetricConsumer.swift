import Foundation
import Clairvoyant
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias HistoryDecodingRoutine = (MetricConsumer, MetricId, MetricHistoryRequest) async throws -> [Timestamped<String>]

/**
 The main connection to a metric server.
 */
public actor MetricConsumer {

    /// The url to the server where the metrics are exposed
    private(set) public var serverUrl: URL

    /// The provider of access tokens to get metrics
    private(set) public var accessProvider: RequestAccessProvider

    /// The url session used for requests
    private(set) public var session: URLSession

    /// The encoder used for encoding outgoing data
    public let decoder: BinaryDecoder

    /// The decoder used for decoding received data
    public let encoder: BinaryEncoder
    
    public nonisolated let customTypeHandler: CustomTypeHandler

    /**
     Create a metric consumer.

     - Parameter url: The url to the server where the metrics are exposed
     - Parameter accessProvider: The provider of access tokens to get metrics
     - Parameter session: The url session to use for the requests
     - Parameter encoder: The encoder to use for encoding outgoing data
     - Parameter decoder: The decoder to decode received data
     - Parameter customTypeRegistation: A closure to register all custom types which should be decodable
     */
    public init(
        url: URL,
        accessProvider: RequestAccessProvider,
        session: URLSession = .shared,
        encoder: BinaryEncoder = JSONEncoder(),
        decoder: BinaryDecoder = JSONDecoder(),
        customTypeRegistation: (inout CustomTypeRegistrar) -> Void = { _ in }) {

            self.serverUrl = url
            self.accessProvider = accessProvider
            self.session = session
            self.decoder = decoder
            self.encoder = encoder
            self.customTypeHandler = .init(customTypeRegistation)
    }
    
    /**
     Create a metric consumer.

     - Parameter url: The url to the server where the metrics are exposed
     - Parameter accessProvider: The provider of access tokens to get metrics
     - Parameter session: The url session to use for the requests
     - Parameter encoder: The encoder to use for encoding outgoing data
     - Parameter decoder: The decoder to decode received data
     - Parameter customTypes: The handler for all custom types
     */
    public init(
        url: URL,
        accessProvider: RequestAccessProvider,
        session: URLSession = .shared,
        encoder: BinaryEncoder = JSONEncoder(),
        decoder: BinaryDecoder = JSONDecoder(),
        customTypes: CustomTypeHandler) {
            self.serverUrl = url
            self.accessProvider = accessProvider
            self.session = session
            self.decoder = decoder
            self.encoder = encoder
            self.customTypeHandler = customTypes
    }

    /**
     Set the url to the server.
     - Parameter url: The url of the server
     */
    public func set(serverUrl: URL) {
        self.serverUrl = serverUrl
    }

    /**
     Set the access provider.
     - Parameter accessProvider: The provider to handle access control
     */
    public func set(accessProvider: RequestAccessProvider) {
        self.accessProvider = accessProvider
    }

    /**
     Set the session to use for requests.
     - Parameter session: The new session to use for the requests
     - Note: Requests in progress will finish with the old session.
     */
    public func set(session: URLSession) {
        self.session = session
    }

    /**
     Get a list of all metrics available on the server.
     - Returns: A list of available metrics
     - Throws: `MetricError` errors, as well as errors from the decoder
     */
    public func list() async throws -> [MetricInfo] {
        try await post(route: .getMetricList)
    }
    
    /**
     Get a list of all metric infos, including their last value data.
     - Returns: A list of available metrics
     - Throws: `MetricError` errors, as well as errors from the decoder
     */
    public func extendedList() async throws -> [MetricIdHash: ExtendedMetricInfo] {
        try await post(route: .extendedInfoList)
    }

    /**
     Get the info for a metric.
     - Parameter metricId: The id of the metric
     - Returns: The info of the metric
     - Throws: `MetricError` errors, as well as errors from the decoder
     */
    public func info(for metricId: MetricId) async throws -> MetricInfo {
        try await post(route: .getMetricInfo(metricId.hashed()))
    }

    /**
     Get a typed handle to process a specific metric.
     - Parameter id: The id of the metric
     - Parameter name: The optional name of the metric
     - Parameter description: A textual description of the metric
     - Returns: A consumable metric of the specified type.
     */
    public nonisolated func metric<T>(id: MetricId, name: String? = nil, description: String? = nil) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, id: id, name: name, description: description)
    }

    /**
     Get a typed handle to process a specific metric.
     - Parameter info: The info about the metric to create.
     - Returns: A consumable metric with the specified info
     */
    public nonisolated func metric<T>(from info: MetricInfo, as type: T.Type = T.self) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, info: info)
    }

    /**
     Get a typed handle to process a specific metric.

     - Note: To work with custom types, register them using ``register(customType:named:)``.
     - Parameter info: The info about the metric to create.
     - Returns: A consumable metric with the specified info
     - Throws: `MetricError.typeMismatch` if the custom type is not registered.
     */
    public nonisolated func genericMetric(from info: MetricInfo) -> GenericConsumableMetric {
        switch info.dataType {
        case .integer:
            return metric(from: info, as: Int.self)
        case .double:
            return metric(from: info, as: Double.self)
        case .boolean:
            return metric(from: info, as: Bool.self)
        case .string:
            return metric(from: info, as: String.self)
        case .data:
            return metric(from: info, as: Data.self)
        case .customType(named: let name):
            return customTypeHandler.metric(ofTypeNamed: name, info: info, consumer: self)
        case .serverStatus:
            return metric(from: info, as: ServerStatus.self)
        case .httpStatus:
            return metric(from: info, as: HTTPStatusCode.self)
        case .semanticVersion:
            return metric(from: info, as: SemanticVersion.self)
        case .date:
            return metric(from: info, as: Date.self)
        }
    }
    
    func textHistory<T>(for metric: MetricId, request: MetricHistoryRequest, as type: T.Type = T.self) async throws -> [Timestamped<String>] where T : MetricValue {
        try await history(for: metric, request: request, as: type)
            .map { $0.mapValue { "\($0)"} }
    }
    
    /**
     Retrieve the history of a metric, and create a textual description for the values.
     - Parameter metric: The id of the metric
     - Parameter type: The data type of the metric
     - Parameter range: The date interval for which to get the history
     - Parameter limit: The maximum number of entries to get, starting from `range.lowerBound`
     - Returns: The timestamped values in the range, converted to a textual description.
     */
    public func historyDescription(for metric: MetricId, type: MetricType, in range: ClosedRange<Date>, limit: Int? = nil) async throws -> [Timestamped<String>] {
        try await historyDescription(for: metric, type: type, from: range.lowerBound, to: range.upperBound, limit: limit)
    }
    
    /**
     Retrieve the history of a metric, and create a textual description for the values.
     - Parameter metric: The id of the metric
     - Parameter type: The data type of the metric
     - Parameter start: The start date of the history to get
     - Parameter end: The end date of the history request
     - Parameter limit: The maximum number of entries to get, starting from `range.lowerBound`
     - Returns: The timestamped values in the range, converted to a textual description.
     */
    public func historyDescription(for metric: MetricId, type: MetricType, from start: Date, to end: Date, limit: Int? = nil) async throws -> [Timestamped<String>] {
        let request = MetricHistoryRequest(start: start, end: end, limit: limit)
        switch type {
        case .integer:
            return try await textHistory(for: metric, request: request, as: Int.self)
        case .double:
            return try await textHistory(for: metric, request: request, as: Double.self)
        case .boolean:
            return try await textHistory(for: metric, request: request, as: Bool.self)
        case .string:
            return try await textHistory(for: metric, request: request, as: String.self)
        case .data:
            return try await textHistory(for: metric, request: request, as: Data.self)
        case .customType(let named):
            return try await customTypeHandler.history(for: metric, request: request, as: named, consumer: self)
        case .serverStatus:
            return try await textHistory(for: metric, request: request, as: ServerStatus.self)
        case .httpStatus:
            return try await textHistory(for: metric, request: request, as: HTTPStatusCode.self)
        case .semanticVersion:
            return try await textHistory(for: metric, request: request, as: SemanticVersion.self)
        case .date:
            return try await textHistory(for: metric, request: request, as: Date.self)
        }
    }

    /**
     Get the encoded data of the timestamped last value of a metric.
     - Parameter metric: The id of the metric.
     - Returns: The timestamped last value data, or `nil`, if no value exists.
     - Throws: `MetricError`
     */
    public func lastValueData(for metric: MetricId) async throws -> Data? {
        do {
            return try await post(route: .lastValue(metric.hashed()))
        } catch MetricError.noValueAvailable {
            return nil
        }
    }

    /**
     Get a textual representation of the last value for a metric.
     - Parameter metric: The info of the metric
     - Returns: The timestamped text representing the last value
     - Throws: `MetricError`
     */
    public func lastValueDescription(for metric: MetricInfo) async throws -> Timestamped<String>? {
        try await lastValueDescription(for: metric.id, type: metric.dataType)
    }

    /**
     Get a textual representation of the last value for a metric.
     - Parameter metricId: The id of the metric
     - Parameter type: The data type of the metric
     - Returns: The timestamped text representing the last value
     - Throws: `MetricError`
     */
    public func lastValueDescription(for metricId: MetricId, type: MetricType) async throws -> Timestamped<String>? {
        guard let data = try await lastValueData(for: metricId) else {
            return nil
        }
        return describe(data, ofType: type)
    }

    /**
     Get the last value data for all metrics of the server.
     - Returns: A dictionary with the metric ID hash and the metric data
     - Note: If no last value exists for a metric, then the dictionary key will be missing.
     */
    public func lastValueDataForAllMetrics() async throws -> [MetricIdHash : Data] {
        let data = try await post(route: .allLastValues)
        return try decode(from: data)
    }

    public func lastValueDescriptionForAllMetrics() async throws -> [MetricIdHash : Timestamped<String>] {
        let values: [ExtendedMetricInfo] = try await post(route: .extendedInfoList)
        return values.reduce(into: [:]) {
            guard let data = $1.lastValueData else { return }
            $0[$1.info.id] = describe(data, ofType: $1.info.dataType)
        }
    }

    public nonisolated func describe(_ data: Data, ofType dataType: MetricType) -> Timestamped<String> {
        customTypeHandler.describe(data, ofType: dataType, decoder: decoder)
    }

    nonisolated func describe<T>(_ data: Data, as type: T.Type) -> Timestamped<String> where T: MetricValue {
        customTypeHandler.describe(data, as: type, decoder: decoder)
    }

    /**
     - Throws: `MetricError`
     */
    public func lastValue<T>(for metric: MetricId, type: T.Type = T.self) async throws -> Timestamped<T>? where T: MetricValue {
        guard let data = try await lastValueData(for: metric) else {
            return nil
        }
        return try decode(Timestamped<T>.self, from: data)
    }

    /**
     - Throws: `MetricError`
     */
    func historyData(for metric: MetricId, from start: Date, to end: Date, limit: Int?) async throws -> Data {
        let request = MetricHistoryRequest(start: start, end: end, limit: limit)
        return try await historyData(for: metric, request: request)
    }
    
    /**
     - Throws: `MetricError`
     */
    func historyData(for metric: MetricId, request: MetricHistoryRequest) async throws -> Data {
        let body = try encode(request)
        return try await post(route: .metricHistory(metric.hashed()), body: body)
    }

    /**
     Get the history of the metric within a specified range.
     
     - Parameter metric: The metric id
     - Parameter range: The start and end date of the history to get
     - Parameter limit: The maximum number of items to get, starting from `range.lowerbound`
     - Parameter type: The data type of the metric
     - Note: If you need to get a limited number of items starting from the end point of the range, then use ``history(for:start:end:limit:type:)``
     - Throws: `MetricError`
     */
    public func history<T>(for metric: MetricId, in range: ClosedRange<Date>, limit: Int? = nil, as type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let request = MetricHistoryRequest(range, limit: limit)
        return try await history(for: metric, request: request)
    }
    
    func history<T>(for metric: MetricId, request: MetricHistoryRequest, as type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let data = try await historyData(for: metric, request: request)
        return try decode(from: data)
    }
    
    /**
     Get the history of the metric within a specified range.
     
     - Parameter metric: The metric id
     - Parameter start: The start date of the history to get
     - Parameter end: The end date of the history request
     - Parameter limit: The maximum number of items to get, starting from `start`
     - Parameter type: The data type of the metric
     - Note: The `start` date may be after the `end` date. The returned array is always sorted from `start` to `end`
     - Throws: `MetricError`
     */
    public func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int? = nil, type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let data = try await historyData(for: metric, from: start, to: end, limit: limit)
        return try decode(from: data)
    }

    private func post<T>(route: ServerRoute, body: Data? = nil) async throws -> T where T: Decodable {
        let data = try await post(route: route, body: body)
        return try decode(from: data)
    }

    /**
     - Throws: `MetricError`
     */
    private func post(route: ServerRoute, body: Data? = nil) async throws -> Data {
        let url = serverUrl.appendingPathComponent(route.rawValue)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        accessProvider.addAccessDataToMetricRequest(&request, route: route)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MetricError.requestFailed
            }
            if response.statusCode == 200 {
                return data
            }
            if let metricError = MetricError(statusCode: response.statusCode) {
                throw metricError
            }
            throw MetricError.requestFailed
        } catch let error as MetricError {
            throw error
        } catch {
            throw MetricError.requestFailed
        }
    }

    /**
     - Throws: `MetricError`
     */
    private func decode<T>(_ type: T.Type = T.self, from data: Data) throws -> T where T: Decodable {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    /**
     - Throws: `MetricError`
     */
    private func encode<T>(_ value: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(value)
        } catch {
            throw MetricError.failedToEncode
        }
    }
}
