import Foundation
import Clairvoyant

public protocol ConsumerNetworkInterface {
    
    func post(route: ServerRoute, body: Data?) async throws -> Data
}
