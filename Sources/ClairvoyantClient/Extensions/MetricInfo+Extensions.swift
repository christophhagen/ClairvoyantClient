import Foundation
import Clairvoyant

extension Sequence where Element == MetricInfo {

    func dict() -> [MetricId : MetricDetails] {
        reduce(into: [:]) { $0[$1.id] = $1.details }
    }

    func set() -> Set<MetricId> {
        .init(map { $0.id })
    }
}
