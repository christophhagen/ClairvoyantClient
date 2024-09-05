import Foundation
import Clairvoyant

final class Client {

    private let network: ConsumerNetworkInterface

    /// The encoder used for encoding outgoing data
    let decoder: AnyBinaryDecoder

    /// The decoder used for decoding received data
    private let encoder: AnyBinaryEncoder

    init(network: ConsumerNetworkInterface, encoder: AnyBinaryEncoder, decoder: AnyBinaryDecoder) {
        self.network = network
        self.encoder = encoder
        self.decoder = decoder
    }

    private func post<Input, Output>(route: ServerRoute, input: Input) async throws -> Output where Input: Encodable, Output: Decodable {
        let body = try encoder.encode(input)
        return try await post(route: route, body: body)
    }

    // MARK: Retrieving data

    func serverMetrics() async throws -> [MetricInfo] {
        try await post(route: .getMetricList)
    }

    func updates(metrics: [MetricId : MetricState], limit: Int? = nil) async throws -> [MetricId: MetricUpdate] {
        let request = ServerSyncRequest(metrics: metrics, maximumNumberOfUpdates: limit)
        return try await post(route: .updates, input: request)
    }

    // MARK: Internal helper

    private func post<T>(route: ServerRoute, body: Data? = nil) async throws -> T where T: Decodable {
        let data = try await network.post(route: route, body: body)
        return try decode(from: data)
    }

    /**
     - Throws: `MetricError`
     */
    func decode<T>(_ type: T.Type = T.self, from data: Data) throws -> T where T: Decodable {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    /**
     - Throws: `MetricError`
     */
    private func encode<T>(_ value: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(value)
        } catch {
            throw MetricError.failedToEncode
        }
    }
}
