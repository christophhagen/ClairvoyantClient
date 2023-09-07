import Foundation
import Clairvoyant
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 A generic type to add access control information to outgoing requests.

 The protocol should be implemented to provide authentication to outgoing metric requests.
 */
public protocol RequestAccessProvider {

    /**
     Add authentication to a metric request.
     - Parameter metricRequest: The request to modify with access control information
     - Parameter route: The server route being called by the request.
     */
    func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest, route: ServerRoute)
}

