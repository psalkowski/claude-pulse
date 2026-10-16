import XCTest

private final class StallingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    func testStalledRequestGivesUpAtTheDeadline() async {
        let configuration = UsageClient.configuration(deadline: 1)
        configuration.protocolClasses = [StallingProtocol.self]
        var client = UsageClient()
        client.session = URLSession(configuration: configuration)
        let started = Date()

        do {
            _ = try await client.fetch(accessToken: "token")
            XCTFail("a stalled request must not succeed")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
