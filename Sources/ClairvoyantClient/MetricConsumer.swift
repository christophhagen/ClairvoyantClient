import Foundation
import Clairvoyant
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

    /// Custom mappings to create consumable metrics for types
    private var customTypeConstructors: [String : (MetricInfo) -> GenericConsumableMetric]

    /// Custom mappings to create consumable metrics for types
    private var customTypeDescriptors: [String : (Data) -> Timestamped<String>]

    /**
     Create a metric consumer.

     - Parameter url: The url to the server where the metrics are exposed
     - Parameter accessProvider: The provider of access tokens to get metrics
     - Parameter session: The url session to use for the requests
     - Parameter encoder: The encoder to use for encoding outgoing data
     - Parameter decoder: The decoder to decode received data
     */
    public init(
        url: URL,
        accessProvider: RequestAccessProvider,
        session: URLSession = .shared,
        encoder: BinaryEncoder = JSONEncoder(),
        decoder: BinaryDecoder = JSONDecoder()) {

            self.serverUrl = url
            self.accessProvider = accessProvider
            self.session = session
            self.decoder = decoder
            self.encoder = encoder
            self.customTypeConstructors = [:]
            self.customTypeDescriptors = [:]
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
    public func metric<T>(id: MetricId, name: String? = nil, description: String? = nil) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, id: id, name: name, description: description)
    }

    /**
     Get a typed handle to process a specific metric.
     - Parameter info: The info about the metric to create.
     - Returns: A consumable metric with the specified info
     */
    public func metric<T>(from info: MetricInfo, as type: T.Type = T.self) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, info: info)
    }

    /**
     Get a typed handle to process a specific metric.

     - Note: To work with custom types, register them using ``register(customType:named:)``.
     - Parameter info: The info about the metric to create.
     - Returns: A consumable metric with the specified info
     - Throws: `MetricError.typeMismatch` if the custom type is not registered.
     */
    public func genericMetric(from info: MetricInfo) throws -> GenericConsumableMetric {
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
            guard let closure = customTypeConstructors[name] else {
                throw MetricError.typeMismatch
            }
            return closure(info)
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

    /**
     Register a custom type.

     Call this function with your custom types so that generic consumable metrics can be created using ``genericMetric(from:)``.

     ```
     let metricInfo = MetricInfo(id: "my.log", dataType: .custom("MyType"))

     consumer.register(customType: MyType.self, named: "MyType")
     let myMetric = consumer.genericMetric(from: description)
     ```

     - Parameter customType: The custom metric type to register.
     */
    public func register<T>(customType: T.Type) where T: MetricValue {
        let typeName = customType.valueType.rawValue
        customTypeConstructors[typeName] = { info in
            return ConsumableMetric<T>(consumer: self, info: info)
        }
        customTypeDescriptors[typeName] = { [weak self] data in
            guard let self else {
                return .init(value: "Internal error")
            }
            return self.describe(data, as: T.self)
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

    public func describe(_ data: Data, ofType dataType: MetricType) -> Timestamped<String> {
        switch dataType {
        case .integer:
            return describe(data, as: Int.self)
        case .double:
            return describe(data, as: Double.self)
        case .boolean:
            return describe(data, as: Bool.self)
        case .string:
            return describe(data, as: String.self)
        case .data:
            return describe(data, as: Data.self)
        case .customType(named: let name):
            guard let closure = customTypeDescriptors[name] else {
                return .init(value: "Unknown type")
            }
            return closure(data)
        case .serverStatus:
            return describe(data, as: ServerStatus.self)
        case .httpStatus:
            return describe(data, as: HTTPStatusCode.self)
        case .semanticVersion:
            return describe(data, as: SemanticVersion.self)
        case .date:
            return describe(data, as: Date.self)
        }
    }

    nonisolated func describe<T>(_ data: Data, as type: T.Type) -> Timestamped<String> where T: MetricValue {
        guard let decoded = try? decoder.decode(Timestamped<T>.self, from: data) else {
            return .init(value: "Decoding error")
        }
        return decoded.mapValue { "\($0)" }
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
    func historyData(for metric: MetricId, in range: ClosedRange<Date>, limit: Int?) async throws -> Data {
        let request = MetricHistoryRequest(range, limit: limit)
        let body = try encode(request)
        return try await post(route: .metricHistory(metric.hashed()), body: body)
    }

    /**
     - Throws: `MetricError`
     */
    public func history<T>(for metric: MetricId, in range: ClosedRange<Date>, limit: Int? = nil, type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let data = try await historyData(for: metric, in: range, limit: limit)
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
