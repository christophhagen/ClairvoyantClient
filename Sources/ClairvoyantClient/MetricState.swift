import Foundation
import Clairvoyant

public struct MetricState {

    public let valueType: MetricType

    /**
     The timestamp of the last value present on the client.

     This value is used to determine the values to send to the client.

     If no value is present, then the client has no values stored,
     so values from the beginning (`Date.distantPast`) should be returned
     */
    public let lastValueTimestamp: Date?

    /**
     The timestamp of the last sync the client did for this metric
     
     This value is used to determine the deletions to send to the client.
     
     If no timestamp is present, then the client has incomplete state,
     and only expects the last value of the metric.
     */
    public let lastSyncTimestamp: Date?
}

extension MetricState: Codable {

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.valueType = try container.decode()
        self.lastValueTimestamp = try container.decodeIfPresent()
        self.lastSyncTimestamp = try container.decodeIfPresent()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(valueType)
        try container.encodeIfPresent(lastValueTimestamp)
        try container.encodeIfPresent(lastSyncTimestamp)
    }
}

