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

public struct MetricUpdate {
    
    /// The intervals deleted from this metric since the last update
    public let deletions: [Timestamped<ClosedRange<Date>>]

    /// The new values provided by the server
    public let values: [Timestamped<Data>]

    /// Indicate if there are more updates to get for this metric
    public let hasMoreUpdates: Bool
}

extension MetricUpdate: Codable {

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deletions = try container.decode(forKey: .deletions, or: [])
        self.values = try container.decode(forKey: .values, or: [])
        self.hasMoreUpdates = try container.decode(forKey: .hasMoreUpdates, or: false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !deletions.isEmpty {
            try container.encode(deletions, forKey: .deletions)
        }
        if !values.isEmpty {
            try container.encode(values, forKey: .values)
        }
        if hasMoreUpdates {
            try container.encode(true, forKey: .hasMoreUpdates)
        }
    }

    enum CodingKeys: Int, CodingKey {
        case deletions = 1
        case values = 2
        case hasMoreUpdates = 3
    }
}
