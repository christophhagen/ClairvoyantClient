import Foundation
import Clairvoyant

/**
 Keep track of remote metrics.

 A metric on the remote can be changed in two ways:
 - Adding a new value (to the end, with a more current timestamp)
 - Deleting an interval of values

 To ensure that a client metric remains in sync with the server metric, it must:
 - Delete all intervals of values in the same way as the server
 - Add new values (to the end)

 The order of the operations is only important when performing inserts and deletions around the current value.
 - For deletion intervals strictly before the current value (so that it is not deleted) the values can just be deleted on the client
 - Deletion intervals in the future of the local current value can be ignored, as all future values will be received when querying new values
 - Deletion intervals around the current value will be applied locally, moving the current value back to the beginning of the deletion interval.

 The above procedure is only applicable for metrics with a complete local history.
 When a new metric is added on the server (or the client syncs for the first time), then no history is available yet.
 In this case, the client will only download the latest values for the remote metric to provide the `lastValue` poperties,
 and other ignore updates from the server, until a full sync is performed.

 This sync can be performed for each metric separately, and will query history batches starting from the oldest, until
 the metric is up to date with the server.

 The client requires additional storage to keep this sync state:
 - An indicator if the metric is fully synced
 - The last value data for each incomplete metric (may not be persisted)
 - The current state of the metric can be determined from local storage
 */
public actor RemoteStorage<Storage> where Storage: MetricStorage {

    private let local: Storage

    private let network: ConsumerNetworkInterface

    /// The encoder used for encoding outgoing data
    private let decoder: AnyBinaryDecoder

    /// The decoder used for decoding received data
    private let encoder: AnyBinaryEncoder

    private let customTypes: [MetricType : CustomTypeHandle]

    /**
     Cache of the sync times for each metric.

     The timestamp is sent to the server, so that it can determine which deletion intervals are of interest.
     Since this timestamp is not stored persistently, the timestamp of the last value will be used on the first run.
     This assumes that the last sync was completed successfully, otherwise deletions up to the last value timestamp
     will not be mirrored on the client.
     */
    private var lastSyncTimes: [MetricId : Date]

    /// The last values of each incomplete metric (not persisted)
    private var lastValues: [MetricId: AnyTimestamped]

    public init(localStorage: Storage, network: ConsumerNetworkInterface, encoder: AnyBinaryEncoder, decoder: AnyBinaryDecoder, customTypes: CustomTypeCollection = .init()) {
        self.local = localStorage
        self.network = network
        self.encoder = encoder
        self.decoder = decoder
        self.customTypes = customTypes.customTypes
        self.lastSyncTimes = [:]
        self.lastValues = [:]
        #warning("Load data from persistent storage")
    }

    // MARK: Data updates

    /**
     Check the server for new, updated or deleted metrics.
     */
    public func syncLocalMetricsListWithServer() async throws {
        let serverMetrics = try await retrieveServerMetrics().dict()
        let clientMetrics = try local.metrics()

        // Compare metrics for inserts, updates, and deletes
        var deletedMetrics: [MetricId] = []
        let updatedMetrics: [(old: MetricInfo, new: MetricDetails)] = clientMetrics.compactMap { oldInfo in
            guard let details = serverMetrics[oldInfo.id] else {
                deletedMetrics.append(oldInfo.id)
                return nil
            }
            guard details != oldInfo.details else {
                return nil
            }
            return (oldInfo, details)
        }
        let existingIds = clientMetrics.set()
        let addedMetrics: [MetricInfo] = serverMetrics.compactMap {
            guard !existingIds.contains($0.key) else {
                return nil
            }
            return .init(id: $0.key, details: $0.value)
        }

        try delete(metrics: deletedMetrics)
        try add(metrics: addedMetrics)
        try update(metrics: updatedMetrics)
    }

    /**
     Update the state of all local metrics to match the server.

     - Parameter maximumNumberOfUpdatesPerRequest: The number of updates to include in the server response.
     - Returns: The total number of updates performed

     Two things must be updated for each metric:
     - The new values added to the metric since the last sync.
     - The intervals (before the last value) that the server deleted since the last sync.

     The client sends three pieces of information to the server (for each metric)
     - The timestamp of the last value
     - The timestamp of the last sync
     - The type of the metric

     If the type doesn't match, then the server doesn't send any updates for this metric,
     since this would lead to decoding errors on the client.

     The server keeps a separate metric which stores all intervals of the history that have been deleted.
     Given the timestamp of the last sync and the last value, the server sends the deletion intervals to the server.
     Only deletion intervals newer that the last sync are sent, and only those that are not fully newer that the last value on the client
     (otherwise the deletion interval has no effect and can be ignored).

     In addition to the information about deletions, the server also sends new values to the client.
     It only sends values after the timestamp of the last value on the client.

     For each request, the client can specify the maximum number of updates to include in the response.
     The server will process each metric, beginning with deletions and then new values, until the number of updates is reached.

     If there are no more updates (deletions or new values) for a metric, then the server sets a flag in the response for each metric.

     The client will perform the received updates by first performing the deletions on the local storage, then adding the new values.
     It then updates the last sync time for the metrics in the response, as well as the last value timestamps.
     If the server signals that a metric has no more updates, then the metric is ignored for this sync.
     The client repeats the sync process untilt all metrics are processed.
     */
    @discardableResult
    public func updateAllMetrics(maximumNumberOfUpdatesPerRequest: Int = 1000) async throws -> Int {
        // Determine last timestamp for all local metrics
        var metricsToUpdate: [MetricId : MetricState] = try metrics().reduce(into: [:]) { dict, info in
            let id = info.id
            let timestamp = try lastValues[id]?.timestamp ?? local.timestampOfLastValue(for: id)
            // Note: If the metric has no value in `lastSyncTimes`, then
            // the server will only return the latest value
            dict[id] = .init(
                valueType: info.valueType,
                lastValueTimestamp: timestamp,
                lastSyncTimestamp: lastSyncTimes[id])
        }

        var totalNumberOfUpdates = 0
        // Repeat until server has no more updates
        while !metricsToUpdate.isEmpty {
            // Send timestamps to server and request updated values
            let response = try await retrieveUpdates(to: metricsToUpdate, limit: maximumNumberOfUpdatesPerRequest)
            var numberOfUpdates = 0
            // Save received values and delete missing chunks
            for (id, update) in response {
                // Note: Even though
                numberOfUpdates += update.numberOfUpdates
                guard let state = metricsToUpdate[id] else {
                    // Updates received for metric that was not requested
                    // TODO: Log this somewhere?
                    print("Update received for unknown metric \(id)")
                    continue
                }
                metricsToUpdate[id] = try integrate(update: update, for: id, from: state)
            }
            totalNumberOfUpdates += numberOfUpdates
            // Check if some metrics were not included in the response
            // due to the update limit
            guard numberOfUpdates == maximumNumberOfUpdatesPerRequest else {
                continue
            }
            // Otherwise remove the metrics not included in the response (not included means no updates)
            metricsToUpdate = metricsToUpdate.filter { response[$0.key] != nil }
        }
        return totalNumberOfUpdates
    }

    private func didCompleteUpdatesToLastSyncTimes() {
        #warning("Persist last sync times")
    }

    private func integrate(update: MetricUpdate, for id: MetricId, from state: MetricState) throws -> MetricState? {
        // Remove all deleted values
        for deletion in update.deletions {
            try local.deleteHistory(for: id, from: deletion.value.lowerBound, to: deletion.value.upperBound)
        }
        if let lastDeletion = update.deletions.last {
            // Forward the sync state to reflect the new information
            lastSyncTimes[id] = lastDeletion.timestamp
        }
        if lastSyncTimes[id] == nil {
            // Incomplete metric, only update last value cache

            guard let value = update.values.last else {
                // Server has no last value for the metric,
                // so it can be treated as fully synced
                lastSyncTimes[id] = .now
                return nil
            }
            try add(lastValue: value, to: id, valueType: state.valueType)
            // Incomplete metric has no more updates, so exclude from next iteration
            return nil
        }

        // Decode all new values and add them to the metric
        try add(values: update.values, to: id, valueType: state.valueType)

        // Update the metric state
        guard update.hasMoreUpdates else {
            // We don't need to update the metric further
            return nil
        }
        let valueTimestamp = update.values.last?.timestamp ?? state.lastValueTimestamp
        let syncTimestamp = update.deletions.last?.timestamp ?? state.lastSyncTimestamp
        return .init(
            valueType: state.valueType,
            lastValueTimestamp: valueTimestamp,
            lastSyncTimestamp: syncTimestamp)
    }

    public enum HistoryRequestDirection {
        case oldestFirst
        case newestFirst
    }

    /**
     Get a number of missing values for a metric.

     Use this function repeatedly to get all history values for a metric.

     The client automatically starts from the newest local value and works forwards.
     */
    @discardableResult
    public func getMissingHistoryBatch<T>(for metric: MetricId, limit: Int, type: T.Type) async throws -> Int where T: MetricValue {
        // Determine missing interval for metric
        let newestValue: Timestamped<T>? = try local.lastValue(for: metric)
        let newestTimestamp = newestValue?.timestamp ?? .distantFuture

        // Request interval
        let batch: [Timestamped<T>] = try await retrieveHistory(metric: metric, start: newestTimestamp, end: .distantFuture, limit: limit)

        if !batch.isEmpty {
            // Add interval to local storage
            try local.store(batch, for: metric)
        }

        if batch.count < limit {
            // No more updates, fully synced
            lastSyncTimes[metric] = .now
        }

        // Return number of added values
        return batch.count
    }

    // MARK: Internal storage interactions

    private func delete(metrics: [MetricId]) throws {
        for metric in metrics {
            try delete(metric)
        }
    }

    private func add(metrics: [MetricInfo]) throws {
        for info in metrics {
            try addOrUpdate(metric: info)
            // Note: The added metric will be treated
            // as an incomplete metric, since no value 
            // is set in `lastSyncTimes`
        }
    }

    private func update(metrics: [(old: MetricInfo, new: MetricDetails)]) throws {
        for (info, newDetails) in metrics {
            if info.valueType != newDetails.valueType {
                // Delete old metric data
                try delete(info.id)
            }
            // Creating a metric updates the name and description
            try addOrUpdate(metric: .init(id: info.id, details: newDetails))
        }
    }

    /**
     Internal function to delete a metric from the local storage if it has been deleted on the server
     */
    private func delete(_ metric: MetricId) throws {
        try local.delete(metric: metric)
        lastSyncTimes[metric] = nil
    }

    private func addOrUpdate(metric info: MetricInfo) throws {
        guard let handle = customTypes[info.valueType] else {
            print("No handle for \(info.valueType)")
            return
        }
        try handle.create(metric: info, in: local)
    }

    @discardableResult
    private func metric<T>(_ info: MetricInfo, type: T.Type) throws -> Metric<T> where T: MetricValue {
        try local.metric(info: info, type: T.self)
    }

    private func add(values: [Timestamped<Data>], to id: MetricId, valueType: MetricType) throws {
        guard let handle = customTypes[valueType] else {
            print("No handle for \(valueType)")
            return
        }
        guard let lastValue = try handle.decode(values, for: id, using: decoder, andStoreIn: local) else {
            return
        }
        // Update to the most recent value
        lastValues[id] = lastValue
    }

    private func add(lastValue: Timestamped<Data>, to id: MetricId, valueType: MetricType) throws {
        guard let handle = customTypes[valueType] else {
            print("No handle for \(valueType)")
            return
        }
        // Last values for incomplete metrics are only stored in cache,
        // and not written to disk, since we would then not be able to
        // add older values during a full sync
        // Note: The listeners for incomplete metrics are not called, since
        // they are managed by the local storage
        #warning("Call update listeners for incomplete metrics")
        lastValues[id] = try handle.decode(lastValue: lastValue, using: decoder)
    }

    // MARK: Network requests

    private func retrieveServerMetrics() async throws -> [MetricInfo] {
        let data = try await network.post(route: .getMetricList, body: nil)
        return try decoder.decode(from: data)
    }

    private func retrieveUpdates(to metrics: [MetricId : MetricState], limit: Int? = nil) async throws -> [MetricId: MetricUpdate] {
        let request = ServerSyncRequest(metrics: metrics, maximumNumberOfUpdates: limit)
        return try await post(route: .updates, input: request)
    }

    private func retrieveHistory<T>(metric: MetricId, start: Date, end: Date, limit: Int?) async throws -> [Timestamped<T>] where T: Decodable {
        let request = MetricHistoryRequest(start: start, end: end, limit: limit)
        return try await post(route: .history(metric), input: request)
    }

    private func post<Input, Output>(route: ServerRoute, input: Input) async throws -> Output where Input: Encodable, Output: Decodable {
        let body = try encoder.encode(input)
        let data = try await network.post(route: route, body: body)
        return try decoder.decode(from: data)
    }
}

extension RemoteStorage: AsyncMetricStorage {
    
    public func metrics() throws -> [MetricInfo] {
        try local.metrics()
    }

    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) throws -> AsyncMetric<T> where T : MetricValue {
        let syncMetric = try local.metric(id, name: name, description: description, type: type)
        return .init(storage: self, info: syncMetric.info)
    }

    public func delete(metric id: MetricId) throws {
        throw MetricError.accessDenied // Updating not supported for now
    }

    public func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T : MetricValue {
        throw MetricError.accessDenied // Updating not supported for now
    }
    
    public func store<S, T>(_ values: S, for metric: MetricId) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        throw MetricError.accessDenied // Updating not supported for now
    }

    public func timestampOfLastValue(for metric: MetricId) throws -> Date? {
        try local.timestampOfLastValue(for: metric)
    }

    public func lastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T : MetricValue {
        // First try to hit the cache before querying the local storage
        try (lastValues[metric] as? Timestamped<T>) ?? local.lastValue(for: metric)
    }
    
    public func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int?) throws -> [Timestamped<T>] where T : MetricValue {
        // For now the whole history is kept locally, so we just return the values
        // In the future, the local cache will be queried first, and if no data exists, then the
        // remote metric will be checked
        try local.history(for: metric, from: start, to: end, limit: limit)
    }
    
    public func deleteHistory(for metric: MetricId, from start: Date, to end: Date) throws {
        throw MetricError.accessDenied // Updating not supported for now
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) throws where T : MetricValue {
        try local.add(changeListener: changeListener, for: metric)
    }

    public func setGlobalChangeListener(_ listener: @escaping (MetricId, Date) -> Void) async throws {
        try local.setGlobalChangeListener(listener)
    }

    public func add(deletionListener: @escaping (ClosedRange<Date>) -> Void, for metric: MetricId) throws {
        try local.add(deletionListener: deletionListener, for: metric)
    }

    public func setGlobalDeletionListener(_ listener: @escaping (MetricId, ClosedRange<Date>) -> Void) async throws {
        try local.setGlobalDeletionListener(listener)
    }


}
