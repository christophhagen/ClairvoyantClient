import Foundation
import Clairvoyant
import ClairvoyantClient

final class NetworkMock {
    
    public let serverUrl: URL
    
    /// The authentication manager for the server side
    public let accessManager: RequestAccessManager
    
    /// The authentication manager for the client side
    public let accessProvider: RequestAccessProvider

    /// The metric observer exposed through vapor
    public let observer: MetricObserver

    /// The encoder to use for the response data.
    public let encoder: BinaryEncoder

    /// The encoder to use for the request body decoding.
    public let decoder: BinaryDecoder
    
    init(serverUrl: URL, accessManager: RequestAccessManager, accessProvider: RequestAccessProvider, observer: MetricObserver, encoder: BinaryEncoder? = nil, decoder: BinaryDecoder? = nil) {
        self.serverUrl = serverUrl
        self.accessManager = accessManager
        self.accessProvider = accessProvider
        self.observer = observer
        self.encoder = encoder ?? observer.encoder
        self.decoder = decoder ?? observer.decoder
    }
    
    private func checkAccessToAllMetrics(for request: URLRequest, on route: ServerRoute) throws -> [MetricIdHash] {
        let list = observer.getAllMetricHashes()
        return try accessManager.getAllowedMetrics(for: request, on: route, accessing: list)
    }

    private func getAccessibleMetric(_ request: URLRequest, route: ServerRoute, hash metricIdHash: MetricIdHash) throws -> GenericMetric {
        guard try accessManager.getAllowedMetrics(for: request, on: route, accessing: [metricIdHash])
            .contains(metricIdHash) else {
            throw MetricError.accessDenied
        }
        return try observer.getMetricByHash(metricIdHash)
    }

    // MARK: Coding wrappers

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            throw MetricError.failedToEncode
        }
    }

    private func decode<T>(_ data: Data, as type: T.Type = T.self) throws -> T where T: Decodable {
        do {
            return try decoder.decode(from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }
}

extension NetworkMock: ConsumerNetworkInterface {
    
    func post(route: ServerRoute, body: Data?) async throws -> Data {
        let url = serverUrl.appendingPathComponent(route.rawValue)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        accessProvider.addAccessDataToMetricRequest(&request, route: route)
        
        switch route {
        case .getMetricInfo(let metricIdHash):
            let metric = try getAccessibleMetric(request, route: route, hash: metricIdHash)
            return try encode(metric.info)
            
        case .getMetricList:
            let allowedMetrics = try checkAccessToAllMetrics(for: request, on: route)
            let filteredResult = observer.getListOfRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
                .map { $0.value }
            return try encode(filteredResult)
            
        case .lastValue(let metricIdHash):
            let metric = try getAccessibleMetric(request, route: route, hash: metricIdHash)
            return try await metric.lastValueData().unwrap(orThrow: MetricError.noValueAvailable)
            
        case .allLastValues:
            let allowedMetrics = try checkAccessToAllMetrics(for: request, on: route)
            let values = await observer.getLastValuesOfAllMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try encode(values)
            
        case .extendedInfoList:
            let allowedMetrics = try checkAccessToAllMetrics(for: request, on: route)
            let values = await observer.getExtendedDataOfAllRecordedMetrics()
                .filter { allowedMetrics.contains($0.key) }
            return try encode(values)
            
        case .metricHistory(let metricIdHash):
            let body = try body.unwrap(orThrow: MetricError.requestFailed) // Different error thrown?
            let range: MetricHistoryRequest = try decode(body)
            let metric = try getAccessibleMetric(request, route: route, hash: metricIdHash)
            return await metric.encodedHistoryData(from: range.start, to: range.end, maximumValueCount: range.limit)
        
        case .pushValueToMetric(let metricIdHash):
            // TODO: Fix route and implement logic
            _ = try getAccessibleMetric(request, route: route, hash: metricIdHash)
            return Data()
        }
    }
}


extension Optional {

    func unwrap(orThrow error: Error) throws -> Wrapped {
        guard let s = self else {
            throw error
        }
        return s
    }
}
