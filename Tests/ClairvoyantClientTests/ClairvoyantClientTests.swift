import XCTest
@testable import ClairvoyantClient
import Clairvoyant

final class ClairvoyantClientTests: XCTestCase {
    
    private var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    var logFolder: URL {
        temporaryDirectory.appendingPathComponent("logs")
    }

    override func setUp() async throws {
        try removeAllFiles()
    }

    override func tearDown() async throws {
        try removeAllFiles()
    }

    private func removeAllFiles() throws {
        let url = logFolder
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        MetricObserver.standard = nil
    }
    
    private func makeParts() -> (serverMetric: Metric<Int>, client: MetricConsumer, clientMetric: ConsumableMetric<Int>) {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "observer.log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        
        let metric: Metric<Int> = observer.addMetric(id: "int")
        let network = NetworkMock(
            serverUrl: URL(string: "https://example.com")!,
            accessManager: "MySecret",
            accessProvider: "MySecret",
            observer: observer)
        
        let client = MetricConsumer(network: network)
        let clientMetric: ConsumableMetric<Int> = client.metric(id: metric.id)
        return (metric, client, clientMetric)
    }
    
    func testMetricInfo() async throws {
        let (serverMetric, client, clientMetric) = makeParts()
        
        let info = try await client.info(for: clientMetric.id)
        XCTAssertEqual(info, serverMetric.info)
    }
    
    func testMetricList() async throws {
        let (serverMetric, client, _) = makeParts()
        
        let list = try await client.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first(where: { $0.id == serverMetric.id }), serverMetric.info)
        XCTAssertTrue(list.contains(where: { $0.id == "observer.log" }))
    }
    
    func testLastValue() async throws {
        let (serverMetric, _, clientMetric) = makeParts()
        
        try await serverMetric.update(123)
        
        let lastValue = try await clientMetric.lastValue()
        XCTAssertNotNil(lastValue)
        XCTAssertEqual(lastValue?.value, 123)
    }
    
    func testAllLastValues() async throws {
        let (serverMetric, client, clientMetric) = makeParts()
        
        try await serverMetric.update(123)
        
        let lastValues = try await client.lastValueDataForAllMetrics()
        guard let lastValueData = lastValues[serverMetric.idHash] else {
            XCTFail("No data for last value of metric")
            return
        }
        let lastValue = try await clientMetric.decode(lastValueData: lastValueData)
        XCTAssertEqual(lastValue.value, 123)
    }
    
    func testExtendedInfoList() async throws {
        let (serverMetric, client, clientMetric) = makeParts()
        
        try await serverMetric.update(123)
        
        let list = try await client.extendedList()
        
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains(where: { $0.value.info.id == "observer.log" }))
        
        guard let metricInfo = list[serverMetric.idHash] else {
            XCTFail("Metric not in extended list")
            return
        }
        XCTAssertEqual(metricInfo.info, serverMetric.info)
        
        guard let lastValueData = metricInfo.lastValueData else {
            XCTFail("No last value data")
            return
        }
        print("Here")
        let lastValue = try await clientMetric.decode(lastValueData: lastValueData)
        XCTAssertEqual(lastValue.value, 123)
    }
    
    func testHistory() async throws {
        let (serverMetric, _, clientMetric) = makeParts()
        
        // Add a lot of data points
        // Need to ensure that decoded dates are the same
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970)
        let values = (1...1000).map {
            Timestamped(value: $0, timestamp: now.advanced(by: TimeInterval(-1001+$0)))
        }
        try await serverMetric.update(values)
        
        let full = try await clientMetric.history()
        XCTAssertEqual(full, values)
        
        let part = Array(values[200..<300])
        let start = part.first!.timestamp
        let end = part.last!.timestamp
        
        // Get some results in 'normal' order
        let normalPart = try await clientMetric.history(in: start...end)
        XCTAssertEqual(normalPart, part)
        let limitedNormalPart = try await clientMetric.history(in: start...end, limit: 100)
        XCTAssertEqual(limitedNormalPart, Array(part.prefix(100)))
        
        // Get some results in 'reverse' order
        let reversePart = try await clientMetric.history(from: end, to: start)
        XCTAssertEqual(reversePart, part.reversed())
        let limitedReversePart = try await clientMetric.history(from: end, to: start, limit: 100)
        XCTAssertEqual(limitedReversePart, part.suffix(100).reversed())
    }
    
    func testPush() async throws {
        
        
    }
}
