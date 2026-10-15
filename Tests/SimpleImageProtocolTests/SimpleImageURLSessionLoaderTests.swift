import Foundation
import XCTest
import SimpleImageURLSessionLoader

final class SimpleImageURLSessionLoaderTests: XCTestCase, @unchecked Sendable {
  private func makeLoader() -> SimpleImageURLSessionLoader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return SimpleImageURLSessionLoader(urlSession: URLSession(configuration: configuration))
  }

  func testDeliversChunkedBodyWithThrottledProgress() async throws {
    let url = URL(string: "https://loader.test/large")!
    let chunks = (0..<1024).map { Data(repeating: UInt8($0 % 256), count: 1024) }
    StubURLProtocol.register(.init(chunks: chunks, sendsContentLength: true), for: url)
    let progress = ProgressRecorder()
    let data = try await makeLoader().imageData(for: URLRequest(url: url)) { progress.record($0) }
    XCTAssertEqual(data, chunks.reduce(Data(), +))
    let values = progress.values
    XCTAssertEqual(values.first, 0)
    XCTAssertEqual(values.last, 1)
    XCTAssertEqual(values, values.sorted())
    XCTAssertLessThanOrEqual(values.count, 102, "Progress is throttled to 1% steps, not reported per byte or chunk")
  }

  func testUnknownContentLengthReportsOnlyStartAndEnd() async throws {
    let url = URL(string: "https://loader.test/unknown-length")!
    let chunks = [Data("abc".utf8), Data("def".utf8)]
    StubURLProtocol.register(.init(chunks: chunks, sendsContentLength: false), for: url)
    let progress = ProgressRecorder()
    let data = try await makeLoader().imageData(for: URLRequest(url: url)) { progress.record($0) }
    XCTAssertEqual(data, Data("abcdef".utf8))
    XCTAssertEqual(progress.values, [0, 1])
  }

  func testCancellationThrowsCancellationError() async throws {
    let url = URL(string: "https://loader.test/hangs")!
    StubURLProtocol.register(.init(chunks: [Data("partial".utf8)], sendsContentLength: true, finishes: false), for: url)
    let loader = makeLoader()
    let task = Task { try await loader.imageData(for: URLRequest(url: url)) { _ in } }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError, "\(error)") }
  }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Response {
    var chunks: [Data]
    var sendsContentLength: Bool
    var finishes = true
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var responses: [URL: Response] = [:]

  static func register(_ response: Response, for url: URL) {
    lock.withLock { responses[url] = response }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let response = Self.lock.withLock({ Self.responses[url] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
      return
    }
    let length = response.chunks.reduce(0) { $0 + $1.count }
    let headers = response.sendsContentLength ? ["Content-Length": "\(length)"] : [:]
    let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
    response.chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
    if response.finishes {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}
