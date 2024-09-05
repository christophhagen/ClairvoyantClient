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

 */
public actor RemoteStorage<Storage> where Storage: MetricStorage {

    private let local: Storage

    private let client: Client

    private let customTypes: [MetricType : CustomTypeHandle]

    /**
     Cache of the sync times for each metric.

     The timestamp is sent to the server, so that it can determine which deletion intervals are of interest.
     Since this timestamp is not stored persistently, the timestamp of the last value will be used on the first run.
     This assumes that the last sync was completed successfully, otherwise deletions up to the last value timestamp
     will not be mirrored on the client.
     */
    private var lastSyncTimes: [MetricId : Date] = [:]

    public init(localStorage: Storage, network: ConsumerNetworkInterface, encoder: AnyBinaryEncoder, decoder: AnyBinaryDecoder, customTypes: CustomTypeCollection = .init()) {
        let client = Client(network: network, encoder: encoder, decoder: decoder)
        self.init(localStorage: localStorage, client: client, customTypes: customTypes)
    }

    init(localStorage: Storage, client: Client, customTypes: CustomTypeCollection) {
        self.local = localStorage
        self.client = client
        self.customTypes = customTypes.customTypes
    }

    public func syncLocalMetricsListWithServer() async throws {
        let serverMetrics = try await client.serverMetrics().dict()
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
    public func updateAllMetrics(maximumNumberOfUpdatesPerRequest: Int = 1000) async throws {
        // Determine last timestamp for all local metrics
        var metricsToUpdate: [MetricId : MetricState] = try metrics().reduce(into: [:]) { dict, info in
            let id = info.id
            let timestamp = try local.timestampOfLastValue(for: id) ?? .distantPast
            dict[id] = .init(
                valueType: info.valueType,
                lastValueTimestamp: timestamp,
                lastSyncTimestamp: lastSyncTimes[id] ?? timestamp)
        }
        // Repeat until server has no more updates
        while !metricsToUpdate.isEmpty {
            // Send timestamps to server and request updated values
            let response = try await client.updates(metrics: metricsToUpdate, limit: maximumNumberOfUpdatesPerRequest)

            // Save received values and delete missing chunks
            for (id, state) in metricsToUpdate {
                guard let update = response[id] else {
                    // No update was included from the server,
                    // which means either that the metric was not found, or that
                    // no changes occured
                    // In both cases we don't need to update the metric further
                    metricsToUpdate[id] = nil
                    continue
                }
                // Remove all deleted values
                for deletion in update.deletions {
                    try local.deleteHistory(for: id, from: deletion.value.lowerBound, to: deletion.value.upperBound)
                }
                // Decode all new values and add them to the metric
                try add(values: update.values, to: id, valueType: state.valueType)

                // Update the metric state
                guard update.hasMoreUpdates else {
                    // We don't need to update the metric further
                    metricsToUpdate[id] = nil
                    continue
                }
                let valueTimestamp = update.values.last?.timestamp ?? state.lastValueTimestamp
                let syncTimestamp = update.deletions.last?.timestamp ?? state.lastSyncTimestamp
                metricsToUpdate[id] = .init(
                    valueType: state.valueType,
                    lastValueTimestamp: valueTimestamp,
                    lastSyncTimestamp: syncTimestamp)
            }
        }
    }

    private func delete(metrics: [MetricId]) throws {
        for metric in metrics {
            try delete(metric)
        }
    }

    private func add(metrics: [MetricInfo]) throws {
        for info in metrics {
            try addOrUpdate(metric: info)
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
    }

    private func addOrUpdate(metric info: MetricInfo) throws {
        // TODO: Handle missing type?
        try customTypes[info.valueType]?.create(metric: info, in: local)
    }

    @discardableResult
    private func metric<T>(_ info: MetricInfo, type: T.Type) throws -> Metric<T> where T: MetricValue {
        try local.metric(info: info, type: T.self)
    }

    private func add(values: [Timestamped<Data>], to id: MetricId, valueType: MetricType) throws {
        // TODO: Handle missing type?
        try customTypes[valueType]?.decode(values, for: id, using: client.decoder, andStoreIn: local)
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
        try local.lastValue(for: metric)
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
}
