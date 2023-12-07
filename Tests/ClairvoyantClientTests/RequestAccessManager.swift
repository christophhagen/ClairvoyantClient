import Foundation
import Clairvoyant
import ClairvoyantClient

/**
 A protocol to implement in order to control access to metric data.
 */
public protocol RequestAccessManager {

    /**
     Check a request to get metric info.
     - Parameter request: The incoming request
     - Parameter route: The route being called
     - Parameter metrics: All metrics being accessed for the request
     - Returns: A list of all metrics allowed to access
     */
    func getAllowedMetrics(for request: URLRequest, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash]
}
