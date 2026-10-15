import Foundation
import ImageIO
@testable import SimpleImage
import UIKit
import UniformTypeIdentifiers
import XCTest

enum Fixtures {
  /// A generated 2x2 lossless WebP with red, green, blue, and white pixels.
  static let webp = Data(base64Encoded: "UklGRiwAAABXRUJQVlA4TB8AAAAvAUAAAB8gEEjeHzqN+RcQFPwf3fxHZA/gBgwR/Q8BAA==")!

  @MainActor
  static func image(_ color: UIColor = .red) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
      color.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
  }

  @MainActor
  static func png(_ color: UIColor = .red) -> Data {
    image(color).pngData()!
  }

  @MainActor
  static func gif(_ colors: [UIColor] = [.red, .blue]) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, colors.count, nil)!
    CGImageDestinationSetProperties(destination, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
    ] as CFDictionary)
    for color in colors {
      CGImageDestinationAddImage(destination, image(color).cgImage!, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
      ] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

final class TestMemoryCache: SimpleImageMemoryCaching, @unchecked Sendable {
  private let lock = NSLock()
  private var images: [String: any ProcessedImage] = [:]

  func image(forKey key: String) -> (any ProcessedImage)? { lock.withLock { images[key] } }
  func store(_ image: any ProcessedImage, forKey key: String) { lock.withLock { images[key] = image } }
  func removeImage(forKey key: String) { lock.withLock { images[key] = nil } }
}

actor TestDataCache: SimpleImageDataCaching {
  private var storage: [String: Data] = [:]

  func data(forKey key: String) -> Data? { storage[key] }
  func store(_ data: Data, forKey key: String) { storage[key] = data }
  func removeData(forKey key: String) { storage[key] = nil }
  func containsData(forKey key: String) -> Bool { storage[key] != nil }

  func waitForData(forKey key: String) async {
    while storage[key] == nil { await Task.yield() }
  }
}

actor RecordingTransformer: SimpleImageTransformer {
  let data: Data
  private(set) var count = 0
  init(data: Data) { self.data = data }
  func transform(data: Data) -> Data { count += 1; return self.data }
}

/// Returns its input unchanged and counts invocations.
final class RecordingProcessor: SimpleImageProcessor, @unchecked Sendable {
  let identifier: String
  private let lock = NSLock()
  private var inputs: [any ProcessedImage] = []
  private let output: (any ProcessedImage)?

  init(identifier: String = "recording", output: (any ProcessedImage)? = nil) {
    self.identifier = identifier
    self.output = output
  }

  var count: Int { lock.withLock { inputs.count } }
  var lastInput: (any ProcessedImage)? { lock.withLock { inputs.last } }

  func process(image: any ProcessedImage) -> any ProcessedImage {
    lock.withLock { inputs.append(image) }
    return output ?? image
  }
}

/// Returns a new `UIImage` redrawn from the input's pixels, like a blur would.
final class PixelProcessor: SimpleImageProcessor, @unchecked Sendable {
  let identifier = "pixel"
  private let lock = NSLock()
  private var input: (any ProcessedImage)?

  var lastInput: (any ProcessedImage)? { lock.withLock { input } }

  func process(image: any ProcessedImage) throws -> any ProcessedImage {
    lock.withLock { input = image }
    guard let source = (image as? UIImageConvertible)?.uiImage else { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = source.scale
    return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in source.draw(at: .zero) }
  }
}

func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
  let value = try await expression()
  return try XCTUnwrap(value, file: file, line: line)
}

/// Signals when decoding starts, then waits until cancelled.
actor BlockingDecoder: SimpleImageDecoder {
  private var started = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  nonisolated func canDecode(_ format: SimpleImageFormat) -> Bool { true }
  nonisolated func encode(processedImage: any ProcessedImage) -> Data? { nil }

  func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    started = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
    try await Task.sleep(for: .seconds(60))
    throw SimpleImageError.invalidImageData
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

final class ProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Double] = []
  var values: [Double] { lock.withLock { storage } }
  func record(_ value: Double) { lock.withLock { storage.append(value) } }
}

actor ControlledLoader: SimpleImageLoader {
  private(set) var requestCount = 0
  private var cancellationCount = 0
  private var pending: [URL: CheckedContinuation<Data, Error>] = [:]
  private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func imageData(for request: URLRequest, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> Data {
    let url = request.url!
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        pending[url] = continuation
        requestCount += 1
        progressHandler(0.5)
        let ready = requestWaiters.filter { $0.0 <= requestCount }
        requestWaiters.removeAll { $0.0 <= requestCount }
        ready.forEach { $0.1.resume() }
      }
    } onCancel: {
      Task { await self.cancel(url) }
    }
  }

  func finish(_ url: URL, with data: Data) { pending.removeValue(forKey: url)?.resume(returning: data) }
  private func cancel(_ url: URL) {
    pending.removeValue(forKey: url)?.resume(throwing: CancellationError())
    cancellationCount += 1
    let ready = cancellationWaiters.filter { $0.0 <= cancellationCount }
    cancellationWaiters.removeAll { $0.0 <= cancellationCount }
    ready.forEach { $0.1.resume() }
  }
  func waitForRequests(_ count: Int) async {
    if requestCount >= count { return }
    await withCheckedContinuation { requestWaiters.append((count, $0)) }
  }
  func waitForCancellations(_ count: Int) async {
    if cancellationCount >= count { return }
    await withCheckedContinuation { cancellationWaiters.append((count, $0)) }
  }
}

/// Serves fixed bytes per URL immediately.
actor StubLoader: SimpleImageLoader {
  private let responses: [URL: Data]
  private(set) var requestCount = 0
  init(_ responses: [URL: Data]) { self.responses = responses }

  func imageData(for request: URLRequest, progressHandler: @escaping @Sendable (Double) -> Void) throws -> Data {
    requestCount += 1
    guard let data = responses[request.url!] else { throw URLError(.fileDoesNotExist) }
    return data
  }
}

extension SimpleImageManager {
  static func test(
    loader: SimpleImageLoader,
    memoryCache: SimpleImageMemoryCaching = TestMemoryCache(),
    originalDiskCache: SimpleImageDataCaching = TestDataCache(),
    processedDiskCache: SimpleImageDataCaching = TestDataCache(),
    decoders: [any SimpleImageDecoder] = [UIImageDecoder()],
    transformers: [SimpleImageTransformer] = []
  ) -> SimpleImageManager {
    SimpleImageManager(
      imageLoader: loader,
      memoryCache: memoryCache,
      originalDiskCache: originalDiskCache,
      processedDiskCache: processedDiskCache,
      decoders: decoders,
      imageTransformers: transformers
    )
  }
}
