import Foundation
import Clairvoyant

/**
 The routes existing on a Clairvoyant Vapor server.
 */
public enum ServerRoute {

    /// Send a client state and get updates from the server
    case updates

    /// Get a list of all metrics
    case getMetricList

    /// The full path of the route
    public var rawValue: String {
        switch self {
        case .updates: return Prefix.updates.rawValue
        case .getMetricList: return Prefix.getMetricList.rawValue
        }
    }

    /// The HTTP header key used for access tokens
    public static var headerAccessToken = "token"

    /// The start of the route, excluding hashes
    public var prefix: Prefix {
        switch self {
        case .updates:
            return .updates
        case .getMetricList:
            return .getMetricList
        }
    }

    /// The prefix of a server route
    public enum Prefix: String {
        case updates = "sync"
        case getMetricList = "list"

        /**
         Create a full server route by adding the hash of a metric.
         - Parameter hash: The metric id hash to add.
         - Returns: The full route
         */
        public func with(id: MetricId) -> ServerRoute {
            switch self {
            case .updates: return .updates
            case .getMetricList: return .getMetricList
            }
        }

        /**
         Create a full server route by adding the hash of a metric.
         - Parameter hash: The metric id hash to add.
         - Returns: The full route as a string
         */
        public func appending(id: MetricId) -> String {
            return rawValue + "/" + id.group + "/" + id.id
        }
    }
}

extension ServerRoute: Equatable {

    public static func == (lhs: ServerRoute, rhs: ServerRoute) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension ServerRoute: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension ServerRoute: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
