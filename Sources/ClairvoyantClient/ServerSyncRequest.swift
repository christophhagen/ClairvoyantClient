import Foundation
import Clairvoyant

public struct MetricState {

    public let valueType: MetricType

    public let lastValueTimestamp: Date

    public let lastSyncTimestamp: Date
}

extension MetricState: Codable {

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.valueType = try container.decode()
        self.lastValueTimestamp = try container.decode()
        self.lastSyncTimestamp = try container.decode()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(valueType)
        try container.encode(lastValueTimestamp)
        try container.encode(lastSyncTimestamp)
    }
}


/**
 A request to the server with the local state.

 The server responds with a number of updates.
 */
public struct ServerSyncRequest {

    public let metrics: [MetricId : MetricState]

    /// The maximum number of updates to add in the response
    public let maximumNumberOfUpdates: Int?

    public init(metrics: [MetricId : MetricState], maximumNumberOfUpdates: Int? = nil) {
        self.metrics = metrics
        self.maximumNumberOfUpdates = maximumNumberOfUpdates
    }
}

extension ServerSyncRequest: Codable {

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.metrics = try container.decode()
        self.maximumNumberOfUpdates = try container.decode()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(metrics)
        try container.encode(maximumNumberOfUpdates)
    }
}
