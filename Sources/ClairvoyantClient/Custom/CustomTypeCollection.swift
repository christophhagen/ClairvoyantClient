import Foundation
import Clairvoyant

public struct CustomTypeCollection {

    let customTypes: [MetricType : CustomTypeHandle]

    public init() {
        self.customTypes = [:]
    }

    public init(_ closure: (inout Builder) -> Void) {
        var builder = Builder()
        closure(&builder)
        builder.addWellKnownTypes()
        self.customTypes = builder.customTypes
    }

    public struct Builder {

        var customTypes: [MetricType : CustomTypeHandle] = [:]

        public mutating func add<T>(_ type: T.Type) where T: MetricValue {
            customTypes[type.valueType] = .init(type: type)
        }

        mutating func addWellKnownTypes() {
            add(Int.self)
            add(Double.self)
            add(Bool.self)
            add(String.self)
            add(Data.self)
            add(Date.self)
            add(ServerStatus.self)
            add(HTTPStatusCode.self)
            add(SemanticVersion.self)
        }
    }
}
