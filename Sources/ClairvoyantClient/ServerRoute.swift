import Foundation
import Clairvoyant

/**
 The routes existing on a Clairvoyant Vapor server.
 */
public enum ServerRoute {

    /// Send a client state and get updates from the server
    case updates

    /// Get the info for a metric
    case getMetricInfo(MetricId)

    /// Get a list of all metrics
    case getMetricList

    /// Get the last value of a specific metric
    case lastValue(MetricId)

    /// Get last values of all metrics
    case allLastValues

    /// Get a list of all metrics with their last values
    case extendedInfoList

    /// Get past values of a specific metric
    case metricHistory(MetricId)

    /// Update the value of a metric
    case pushValueToMetric(MetricId)

    /// The full path of the route
    public var rawValue: String {
        switch self {
        case .updates: return Prefix.updates.rawValue
        case .getMetricInfo(let id): return Prefix.getMetricInfo.appending(id: id)
        case .getMetricList: return Prefix.getMetricList.rawValue
        case .lastValue(let id): return Prefix.lastValue.appending(id: id)
        case .allLastValues: return Prefix.allLastValues.rawValue
        case .extendedInfoList: return Prefix.extendedInfoList.rawValue
        case .metricHistory(let id): return Prefix.metricHistory.appending(id: id)
        case .pushValueToMetric(let id): return Prefix.pushValueToMetric.appending(id: id)
        }
    }

    /// The HTTP header key used for access tokens
    public static var headerAccessToken = "token"

    /// The start of the route, excluding hashes
    public var prefix: Prefix {
        switch self {
        case .updates:
            return .updates
        case .getMetricInfo:
            return .getMetricInfo
        case .getMetricList:
            return .getMetricList
        case .lastValue:
            return .lastValue
        case .allLastValues:
            return .allLastValues
        case .extendedInfoList:
            return .extendedInfoList
        case .metricHistory:
            return .metricHistory
        case .pushValueToMetric:
            return .pushValueToMetric
        }
    }

    /// The prefix of a server route
    public enum Prefix: String {
        case updates = "sync"
        case getMetricInfo = "info"
        case getMetricList = "list"
        case lastValue = "last"
        case allLastValues = "last/all"
        case extendedInfoList = "list/extended"
        case metricHistory = "history"
        case pushValueToMetric = "push"

        /**
         Create a full server route by adding the hash of a metric.
         - Parameter hash: The metric id hash to add.
         - Returns: The full route
         */
        public func with(id: MetricId) -> ServerRoute {
            switch self {
            case .updates: return .updates
            case .getMetricInfo: return .getMetricInfo(id)
            case .getMetricList: return .getMetricList
            case .lastValue: return .lastValue(id)
            case .allLastValues: return .allLastValues
            case .extendedInfoList: return .extendedInfoList
            case .metricHistory: return .metricHistory(id)
            case .pushValueToMetric: return .pushValueToMetric(id)
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
