import Foundation
import Clairvoyant
import ClairvoyantClient

extension String: RequestAccessManager {
    
    public func getAllowedMetrics(for request: URLRequest, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        guard let accessToken = request.value(forHTTPHeaderField: ServerRoute.headerAccessToken) else {
            throw MetricError.requestFailed
        }
        guard accessToken == self else {
            // Only the single token is allowed
            throw MetricError.accessDenied
        }
        return metrics
    }
}
