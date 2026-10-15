import Foundation
@testable import SimpleImage
import UIKit
import XCTest

/// Decodes with `UIImageDecoder` and counts invocations.
final class CountingDecoder: SimpleImageDecoder, @unchecked Sendable {
  private let lock = NSLock()
  private var decodes = 0
  var decodeCount: Int { lock.withLock { decodes } }

  func canDecode(_ format: SimpleImageFormat) -> Bool { true }
  func encode(processedImage: any ProcessedImage) -> Data? { UIImageDecoder().encode(processedImage: processedImage) }
  func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    lock.withLock { decodes += 1 }
    return try await UIImageDecoder().decode(rawImage: rawImage)
  }
}

final class DownsampleProcessorTests: XCTestCase {
  @MainActor
  private func png(width: CGFloat, height: CGFloat) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  @MainActor
  func testLargeImagesDownsampleFromBytesKeepingTheAspectRatio() async throws {
    let processor = DownsampleProcessor(maxPixelWidth: 256)
    let rawImage = RawImage(data: png(width: 1000, height: 1500))
    let output = try await processor.process(rawImage: rawImage)
    let image = try XCTUnwrap(output as? UIImage)
    XCTAssertEqual(image.size.width * image.scale, 256, accuracy: 1)
    XCTAssertEqual(image.size.height * image.scale, 384, accuracy: 1)
    XCTAssertEqual(processor.identifier, "downsample-256")
  }

  @MainActor
  func testSmallImagesFallBackToNormalDecoding() async throws {
    let rawImage = RawImage(data: png(width: 100, height: 150))
    let output = try await DownsampleProcessor(maxPixelWidth: 256).process(rawImage: rawImage)
    XCTAssertNil(output)
  }

  @MainActor
  func testAnimatedImagesBecomeAStill() async throws {
    let gif = Fixtures.gif()
    let fromBytes = try await DownsampleProcessor(maxPixelWidth: 2).process(rawImage: RawImage(data: gif))
    XCTAssertTrue(fromBytes is UIImage)
    // An already-decoded animation also comes back as a still.
    let decoded = try await UIImageDecoder().decode(rawImage: RawImage(data: gif))
    let fromImage = try await DownsampleProcessor(maxPixelWidth: 256).process(image: decoded)
    XCTAssertTrue(fromImage is UIImage)
  }

  @MainActor
  func testDataProcessorSkipsTheDecoderAndStillPersistsTheOriginal() async throws {
    let url = URL(string: "https://images.test/downsample")!
    let bytes = png(width: 1000, height: 1500)
    let decoder = CountingDecoder()
    let original = TestDataCache()
    let memory = TestMemoryCache()
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: bytes]),
      memoryCache: memory,
      originalDiskCache: original,
      decoders: [decoder]
    )
    let processor = DownsampleProcessor(maxPixelWidth: 128)
    let output = try await manager.image(request: URLRequest(url: url), processors: [processor])
    let image = try XCTUnwrap(output as? UIImage)
    XCTAssertEqual(image.size.width * image.scale, 128, accuracy: 1)
    XCTAssertEqual(decoder.decodeCount, 0, "the full-size image is never decoded")

    let request = SimpleImageRequest(urlRequest: URLRequest(url: url), processors: [processor])
    await original.waitForData(forKey: request.unprocessedCacheKey)
    let stored = await original.data(forKey: request.unprocessedCacheKey)
    XCTAssertEqual(stored, bytes)
    XCTAssertNil(memory.image(forKey: request.unprocessedCacheKey))
  }

  func testCancellingDuringDownloadNeverDecodes() async throws {
    let loader = ControlledLoader()
    let decoder = CountingDecoder()
    let manager = SimpleImageManager.test(loader: loader, decoders: [decoder])
    let request = URLRequest(url: URL(string: "https://images.test/cancel-decode")!)
    let task = Task { try await manager.image(request: request, processors: [DownsampleProcessor(maxPixelWidth: 64)]) }
    await loader.waitForRequests(1)
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError) }
    await loader.waitForCancellations(1)
    XCTAssertEqual(decoder.decodeCount, 0)
  }
}
