import Foundation
import Clairvoyant

public struct CustomTypeRegistrar {
    
    /// Custom mappings to create consumable metrics for types
    var customTypeConstructors: [String : (MetricConsumer, MetricInfo) -> GenericConsumableMetric] = [:]

    /// Custom mappings to create consumable metrics for types
    var customTypeDescriptors: [String : (BinaryDecoder, Data) -> Timestamped<String>] = [:]
    
    /// Custom mappings to decode the history of custom types
    var customHistoryDescriptors: [String : HistoryDecodingRoutine] = [:]
    
    public mutating func register<T>(customType: T.Type) where T: MetricValue {
        let typeName = customType.valueType.rawValue
        customTypeConstructors[typeName] = { consumer, info in
            return ConsumableMetric<T>(consumer: consumer, info: info)
        }
        customTypeDescriptors[typeName] = { consumer, data in
            consumer.describe(data, as: T.self)
        }
        customHistoryDescriptors[customType.valueType.rawValue] = { consumer, id, request in
            try await consumer.textHistory(for: id, request: request, as: customType.self)
        }
    }
}

public struct CustomTypeHandler {
    
    /// Custom mappings to create consumable metrics for types
    private var customTypeConstructors: [String : (MetricConsumer, MetricInfo) -> GenericConsumableMetric]

    /// Custom mappings to create consumable metrics for types
    private var customTypeDescriptors: [String : (BinaryDecoder, Data) -> Timestamped<String>]
    
    /// Custom mappings to decode the history of custom types
    private var customHistoryDescriptors: [String : HistoryDecodingRoutine]
    
    /**
     Create a handler for custom metric types.
     
     - Parameter registrationCallback: A closure providing the registrar to register all custom types.
     
     Call `register(_:)` for all custom types within the provided closure.
     
     ```
     let handler = CustomTypeHandler() {
        $0.register(MyCustomType.self)
     }
     ```
     */
    public init(_ registrationCallback: (inout CustomTypeRegistrar) -> Void) {
        var registrar = CustomTypeRegistrar()
        registrationCallback(&registrar)
        self.customTypeDescriptors = registrar.customTypeDescriptors
        self.customTypeConstructors = registrar.customTypeConstructors
        self.customHistoryDescriptors = registrar.customHistoryDescriptors
    }
    
    func metric(ofTypeNamed name: String, info: MetricInfo, consumer: MetricConsumer) -> GenericConsumableMetric {
        guard let closure = customTypeConstructors[name] else {
            return UnknownConsumableMetric(consumer: consumer, info: info)
        }
        return closure(consumer, info)
    }
    
    func history(for metric: MetricId, request: MetricHistoryRequest, as type: String, consumer: MetricConsumer) async throws -> [Timestamped<String>] {
        guard let conversion = customHistoryDescriptors[type] else {
            throw MetricError.failedToDecode
        }
        return try await conversion(consumer, metric, request)
    }
    
    private func describe(_ data: Data, ofTypeNamed name: String, decoder: BinaryDecoder) -> Timestamped<String> {
        guard let closure = customTypeDescriptors[name] else {
            return .init(value: "Unknown type")
        }
        return closure(decoder, data)
    }
    
    public func describe(_ data: Data, ofType dataType: MetricType, decoder: BinaryDecoder) -> Timestamped<String> {
        switch dataType {
        case .integer:
            return describe(data, as: Int.self, decoder: decoder)
        case .double:
            return describe(data, as: Double.self, decoder: decoder)
        case .boolean:
            return describe(data, as: Bool.self, decoder: decoder)
        case .string:
            return describe(data, as: String.self, decoder: decoder)
        case .data:
            return describe(data, as: Data.self, decoder: decoder)
        case .customType(named: let name):
            return describe(data, ofTypeNamed: name, decoder: decoder)
        case .serverStatus:
            return describe(data, as: ServerStatus.self, decoder: decoder)
        case .httpStatus:
            return describe(data, as: HTTPStatusCode.self, decoder: decoder)
        case .semanticVersion:
            return describe(data, as: SemanticVersion.self, decoder: decoder)
        case .date:
            return describe(data, as: Date.self, decoder: decoder)
        }
    }

    func describe<T>(_ data: Data, as type: T.Type, decoder: BinaryDecoder) -> Timestamped<String> where T: MetricValue {
        guard let decoded = try? decoder.decode(Timestamped<T>.self, from: data) else {
            return .init(value: "Decoding error")
        }
        return decoded.mapValue { "\($0)" }
    }
}

private extension BinaryDecoder {
    
    func describe<T>(_ data: Data, as type: T.Type) -> Timestamped<String> where T: MetricValue {
        guard let decoded = try? decode(Timestamped<T>.self, from: data) else {
            return .init(value: "Decoding error")
        }
        return decoded.mapValue { "\($0)" }
    }
}
