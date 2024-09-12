import Foundation
import Clairvoyant

public struct MetricUpdate {

    /// The intervals deleted from this metric since the last update
    public let deletions: [Timestamped<ClosedRange<Date>>]

    /// The new values provided by the server
    public let values: [Timestamped<Data>]

    /// Indicate if there are more updates to get for this metric
    public let hasMoreUpdates: Bool

    public init(deletions: [Timestamped<ClosedRange<Date>>], values: [Timestamped<Data>], hasMoreUpdates: Bool) {
        self.deletions = deletions
        self.values = values
        self.hasMoreUpdates = hasMoreUpdates
    }

    public var numberOfUpdates: Int {
        deletions.count + values.count
    }
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
