import Foundation
import Clairvoyant

typealias CustomTypeHandle = (MetricId, Date, Int?, MetricStorage, AnyBinaryEncoder) throws -> [Timestamped<Data>]

func createTypeHandles() -> [MetricType : CustomTypeHandle] {
    var customTypes: [MetricType : CustomTypeHandle] = [:]

    func add<T>(_ type: T.Type) where T: MetricValue {
        customTypes[type.valueType] = { id, start, limit, storage, encoder in
            let history: [Timestamped<T>] = try storage.history(for: id, from: start, to: .distantFuture, limit: limit)
            return try history.mapValues { try encoder.encode($0) }
        }
    }

    add(Int.self)
    add(Double.self)
    add(Bool.self)
    add(String.self)
    add(Data.self)
    add(Date.self)
    add(ServerStatus.self)
    add(HTTPStatusCode.self)
    add(SemanticVersion.self)

    return customTypes
}
