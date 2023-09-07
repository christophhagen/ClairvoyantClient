import Foundation
import Clairvoyant
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension String: RequestAccessProvider {

    /**
     Adds the string as an access token to the url request.

     The string is set as the http header field with the key ``ServerRoute.headerAccessToken``
     */
    public func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest, route: ServerRoute) {
        metricRequest.addValue(self, forHTTPHeaderField: ServerRoute.headerAccessToken)
    }
}
