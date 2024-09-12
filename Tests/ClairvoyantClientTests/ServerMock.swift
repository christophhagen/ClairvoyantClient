import Foundation
import Clairvoyant
import ClairvoyantClient

final class ServerMock {
    
    public let serverUrl: URL
    
    /// The authentication manager for the server side
    public let accessManager: RequestAccessManager
    
    /// The authentication manager for the client side
    public let accessProvider: RequestAccessProvider

    /// The metric observer exposed through vapor
    public let storage: MetricStorage

    /// The encoder to use for the response data.
    public let encoder: AnyBinaryEncoder

    /// The encoder to use for the request body decoding.
    public let decoder: AnyBinaryDecoder

    let customTypes: [MetricType : CustomTypeHandle]

    private var deletions: [MetricId : [Timestamped<ClosedRange<Date>>]] = [:]

    private var lastValueTimestamps: [MetricId : Date] = [:]

    init(serverUrl: URL, accessManager: RequestAccessManager, accessProvider: RequestAccessProvider, storage: MetricStorage, encoder: AnyBinaryEncoder, decoder: AnyBinaryDecoder) throws {
        self.serverUrl = serverUrl
        self.accessManager = accessManager
        self.accessProvider = accessProvider
        self.storage = storage
        self.encoder = encoder
        self.decoder = decoder
        self.customTypes = createTypeHandles()

        try storage.setGlobalDeletionListener { [weak self] id, range in
            guard let self else {
                return
            }
            self.deletions[id] = (self.deletions[id] ?? []) + [Timestamped(value: range)]
        }
        try storage.setGlobalChangeListener { [weak self] id, date in
            guard let self else {
                return
            }
            self.lastValueTimestamps[id] = date
        }
    }
    
    private func checkAccessToAllMetrics(for request: URLRequest, on route: ServerRoute) throws -> [MetricId] {
        let list = try storage.metrics().map { $0.id }
        return try accessManager.getAllowedMetrics(for: request, on: route, accessing: list)
    }

    private func update(for info: MetricInfo, with state: MetricState, maximumUpdateCount: Int) throws -> MetricUpdate {
        // Get one additional deletion as an indicator for future updates
        let deletions = self.deletions[info.id]?
            .drop { $0.timestamp < state.lastSyncTimestamp }
            .prefix(maximumUpdateCount + 1) ?? []

        // More deletions available, return batch
        guard deletions.count < maximumUpdateCount else {
            // Only add partial deletions
            return MetricUpdate(
                deletions: deletions.dropLast(),
                values: [],
                hasMoreUpdates: true)
        }

        guard let handler = customTypes[info.valueType] else {
            print("No handler found for type \(info.valueType)")
            return MetricUpdate(
                deletions: Array(deletions),
                values: [],
                hasMoreUpdates: false)
        }
        
        // Add values until response is full
        let maxValueCount = maximumUpdateCount - deletions.count
        // Get one value more to see if more values exist
        let values = try handler(info.id, state.lastValueTimestamp, maxValueCount + 1, storage, encoder)

        // One value more indicates additional updates
        guard values.count <= maxValueCount else {
            return MetricUpdate(
                deletions: Array(deletions),
                values: values.dropLast(),
                hasMoreUpdates: true)
        }
        // All updates included in batch
        return MetricUpdate(
            deletions: Array(deletions),
            values: Array(values),
            hasMoreUpdates: false)
    }

    private func getUpdates(state clientState: ServerSyncRequest, allowed allowedMetrics: [MetricId]) throws -> [MetricId: MetricUpdate] {
        var remainingUpdates = clientState.maximumNumberOfUpdates ?? Int.max
        var response: [MetricId: MetricUpdate] = [:]
        let metrics = try storage.metrics()
        for (id, state) in clientState.metrics {
            guard let info = metrics.first(where: { $0.id == id }) else {
                // Metric id not found, so ignore in response
                print("Mock: Requested metric \(id) not found")
                continue
            }
            guard allowedMetrics.contains(id) else {
                // No access to metric
                continue
            }
            let update = try self.update(for: info, with: state, maximumUpdateCount: remainingUpdates)
            let updateCount = update.numberOfUpdates
            guard updateCount > 0 else {
                print("Mock: No update for metric: \(id)")
                continue
            }
            remainingUpdates -= updateCount
            response[id] = update
            print("\(updateCount) updates for metric: \(id)")
            guard remainingUpdates > 0 else {
                print("Mock: Maximum number of updates reached for request")
                break
            }
        }
        return response
    }

    // MARK: Coding wrappers

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            throw MetricError.failedToEncode
        }
    }

    private func decode<T>(_ data: Data, as type: T.Type = T.self) throws -> T where T: Decodable {
        do {
            return try decoder.decode(from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }
}

extension ServerMock: ConsumerNetworkInterface {

    private func createRequest(route: ServerRoute, body: Data?) -> URLRequest {
        let url = serverUrl.appendingPathComponent(route.rawValue)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        accessProvider.addAccessDataToMetricRequest(&request, route: route)
        return request
    }

    private func handleUpdate(body: Data?, allowed allowedMetrics: [MetricId]) throws -> Data {
        let body = try body.unwrap(orThrow: MetricError.requestFailed) // Different error thrown?
        let clientState: ServerSyncRequest = try decode(body)
        let updates = try getUpdates(state: clientState, allowed: allowedMetrics)
        return try encode(updates)
    }

    func post(route: ServerRoute, body: Data?) async throws -> Data {
        let request = createRequest(route: route, body: body)

        switch route {
        case .updates:
            let allowedMetrics = try checkAccessToAllMetrics(for: request, on: route)
            return try handleUpdate(body: body, allowed: allowedMetrics)

        case .getMetricList:
            let allowedMetrics = try checkAccessToAllMetrics(for: request, on: route)
            let filteredResult = try storage.metrics()
                .filter { allowedMetrics.contains($0.id) }
            return try encode(filteredResult)
        }
    }
}


extension Optional {

    func unwrap(orThrow error: Error) throws -> Wrapped {
        guard let s = self else {
            throw error
        }
        return s
    }
}

extension MetricStorage {


}
