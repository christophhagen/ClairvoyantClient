import XCTest
import ClairvoyantClient
import Clairvoyant
import MetricFileStorage

extension MetricInfo: CustomStringConvertible {
    public var description: String {
        "\(id.group):\(id.id)<\(valueType)>"
    }
}

final class ClairvoyantClientTests: XCTestCase {
    
    private var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    var serverFolder: URL {
        temporaryDirectory.appendingPathComponent("server")
    }

    var clientFolder: URL {
        temporaryDirectory.appendingPathComponent("client")
    }

    override func setUp() async throws {
        try removeAllFiles()
        self.continueAfterFailure = false
    }

    override func tearDown() async throws {
        try removeAllFiles()
    }

    private func removeAllFiles() throws {
        try remove(folder: clientFolder)
        try remove(folder: serverFolder)
    }

    private func remove(folder: URL) throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private func makeParts() async throws -> (serverMetric: Metric<Int>, client: RemoteStorage<MultiFileStorage>, clientMetric: AsyncMetric<Int>) {
        let serverStorage = try MultiFileStorage(
            folder: serverFolder,
            encoderCreator: JSONEncoder.init,
            decoderCreator: JSONDecoder.init)
        let serverMetric = try serverStorage.metric(id: "int", group: "test", type: Int.self)
        let network = try ServerMock(
            serverUrl: URL(string: "https://example.com")!,
            accessManager: "MySecret",
            accessProvider: "MySecret",
            storage: serverStorage,
            encoder: JSONEncoder(),
            decoder: JSONDecoder())


        let localStorage = try MultiFileStorage(
            folder: clientFolder,
            encoderCreator: JSONEncoder.init,
            decoderCreator: JSONDecoder.init)

        let client = RemoteStorage(localStorage: localStorage, network: network, encoder: JSONEncoder(), decoder: JSONDecoder())
        let clientMetric = try await client.metric(id: serverMetric.id, type: Int.self)
        #warning("Return server storage")
        return (serverMetric, client, clientMetric)
    }
    
    func testMetricInfo() async throws {
        let (serverMetric, client, clientMetric) = try await makeParts()
        
        try await client.syncLocalMetricsListWithServer()
        let info = try await client.metrics().first { $0.id == clientMetric.id }
        XCTAssertEqual(info, serverMetric.info)
    }
    
    func testMetricList() async throws {
        let (serverMetric, client, _) = try await makeParts()

        let list = try await client.metrics()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first, serverMetric.info)
    }
    
    func testLastValue() async throws {
        let (serverMetric, client, clientMetric) = try await makeParts()

        try serverMetric.update(123)

        try await client.syncLocalMetricsListWithServer() // First get metric list
        let clientCount = try await client.metrics().count
        XCTAssertEqual(clientCount, 1)

        try await client.updateAllMetrics() // Then update metrics

        let lastValue = try await clientMetric.currentValue()
        XCTAssertNotNil(lastValue)
        XCTAssertEqual(lastValue?.value, 123)
    }
    /*
    func testAllLastValues() async throws {
        let (serverMetric, client, clientMetric) = try await makeParts()

        try serverMetric.update(123)
        
        let lastValues = try await client.lastValueDataForAllMetrics()
        guard let lastValueData = lastValues[serverMetric.idHash] else {
            XCTFail("No data for last value of metric")
            return
        }
        let lastValue = try await clientMetric.decode(lastValueData: lastValueData)
        XCTAssertEqual(lastValue.value, 123)
    }
    
    func testExtendedInfoList() async throws {
        let (serverMetric, client, clientMetric) = try await makeParts()

        try serverMetric.update(123)
        
        let list = try await client.extendedList()
        
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains(where: { $0.value.info.id == "observer.log" }))
        
        guard let metricInfo = list[serverMetric.id] else {
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
    */
    func testHistory() async throws {
        let (serverMetric, client, clientMetric) = try await makeParts()

        // Add a lot of data points
        // Need to ensure that decoded dates are the same
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970)
        let values = (1...1000).map {
            Timestamped(value: $0, timestamp: now.advanced(by: TimeInterval(-1001+$0)))
        }
        try serverMetric.update(values)

        try await client.updateAllMetrics()

        let full = try await clientMetric.history()
        XCTAssertEqual(full, values)
        
        let part = Array(values[200..<300])
        let start = part.first!.timestamp
        let end = part.last!.timestamp
        
        // Get some results in 'normal' order
        let normalPart = try await clientMetric.history(in: start...end)
        XCTAssertEqual(normalPart, part)
        let limitedNormalPart = try await clientMetric.history(in: start...end, limit: 100)
        XCTAssertEqual(limitedNormalPart, part)
        let moreLimitedNormalPart = try await clientMetric.history(in: start...end, limit: 50)
        XCTAssertEqual(moreLimitedNormalPart, Array(part.prefix(50)))
        
        // Get some results in 'reverse' order
        let reversePart = try await clientMetric.history(from: end, to: start)
        XCTAssertEqual(reversePart, part.reversed())
        let limitedReversePart = try await clientMetric.history(from: end, to: start, limit: 100)
        XCTAssertEqual(limitedReversePart, part.reversed())
        let moreLimitedReversePart = try await clientMetric.history(from: end, to: start, limit: 50)
        XCTAssertEqual(moreLimitedReversePart, Array(reversePart.prefix(50)))
    }
    
    func testPush() async throws {
        
        
    }
}
