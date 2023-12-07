import Foundation
import Clairvoyant
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct URLSessionNetworkInterface {
    
    let serverUrl: URL
    
    let accessProvider: RequestAccessProvider
    
    let session: URLSession
}

extension URLSessionNetworkInterface: ConsumerNetworkInterface {
    
    /**
     - Throws: `MetricError`
     */
    func post(route: ServerRoute, body: Data? = nil) async throws -> Data {
        let url = serverUrl.appendingPathComponent(route.rawValue)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        accessProvider.addAccessDataToMetricRequest(&request, route: route)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MetricError.requestFailed
            }
            if response.statusCode == 200 {
                return data
            }
            if let metricError = MetricError(statusCode: response.statusCode) {
                throw metricError
            }
            throw MetricError.requestFailed
        } catch let error as MetricError {
            throw error
        } catch {
            throw MetricError.requestFailed
        }
    }
}
