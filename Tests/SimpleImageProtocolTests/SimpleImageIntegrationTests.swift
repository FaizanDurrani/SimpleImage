import Foundation
import XCTest
import SimpleImageUIKit
import SimpleImageCache
@testable import SimpleImage
import UIKit

final class SimpleImageIntegrationTests: XCTestCase, @unchecked Sendable {
  @MainActor
  func testCoalescingProgressAndIndependentCancellation() async throws {
    let loader = ControlledLoader()
    let manager = SimpleImageManager.test(loader: loader)
    let request = URLRequest(url: URL(string: "https://images.test/shared")!)
    let cancelled = expectation(description: "Cancelled subscriber completes once")
    cancelled.assertForOverFulfill = true
    let delivered = expectation(description: "Remaining subscriber receives image")
    let progress = ProgressRecorder()
    let first = manager.retrieveImage(request: request) { result in
      guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
      XCTAssertTrue(error is CancellationError)
      cancelled.fulfill()
    }
    let second = manager.retrieveImage(request: request, progressHandler: { progress.record($0) }) { result in
      XCTAssertNotNil(try? result.get())
      delivered.fulfill()
    }
    await loader.waitForRequests(1)
    first.cancel()
    first.cancel()
    await loader.finish(request.url!, with: Fixtures.png())
    await fulfillment(of: [cancelled, delivered], timeout: 3)
    let count = await loader.requestCount
    XCTAssertEqual(count, 1)
    XCTAssertTrue(progress.values.contains(0.5))
    XCTAssertFalse(second.isCancelled)
  }

  @MainActor
  func testCancellingAsyncLoadCancelsUnderlyingLoader() async throws {
    let loader = ControlledLoader()
    let manager = SimpleImageManager.test(loader: loader)
    let request = URLRequest(url: URL(string: "https://images.test/cancel")!)
    let task = Task { try await manager.image(request: request) }
    await loader.waitForRequests(1)
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError) }
    await loader.waitForCancellations(1)
  }

  @MainActor
  func testCacheHitSkipsLoaderAndTransformationRunsOnce() async throws {
    let loader = ControlledLoader()
    let transformer = RecordingTransformer(data: Fixtures.png())
    let manager = SimpleImageManager.test(loader: loader, transformers: [transformer])
    let request = URLRequest(url: URL(string: "https://images.test/cache")!)
    let task = Task { try await manager.image(request: request) }
    await loader.waitForRequests(1)
    await loader.finish(request.url!, with: Data("transformed by source".utf8))
    _ = try await task.value
    _ = try await manager.image(request: request)
    let requests = await loader.requestCount
    let transforms = await transformer.count
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(transforms, 1)
  }

  @MainActor
  func testNativeWebPDecodingThroughManager() async throws {
    let loader = ControlledLoader()
    let manager = SimpleImageManager.test(loader: loader)
    let request = URLRequest(url: URL(string: "https://images.test/native.webp")!)
    let task = Task { try await manager.image(request: request) }
    await loader.waitForRequests(1)
    await loader.finish(request.url!, with: Fixtures.webp)
    let value = try await task.value
    let image = try XCTUnwrap(value as? UIImage)
    XCTAssertEqual(image.cgImage?.width, 2)
    XCTAssertEqual(image.cgImage?.height, 2)
  }

  @MainActor
  func testInvalidDataFailsWithoutCaching() async throws {
    let loader = ControlledLoader()
    let memory = TestMemoryCache()
    let original = TestDataCache()
    let manager = SimpleImageManager.test(loader: loader, memoryCache: memory, originalDiskCache: original)
    let request = URLRequest(url: URL(string: "https://images.test/invalid")!)
    let task = Task { try await manager.image(request: request) }
    await loader.waitForRequests(1)
    await loader.finish(request.url!, with: Data("invalid".utf8))
    do { _ = try await task.value; XCTFail("Expected decoding failure") } catch {}
    let cached = await original.containsData(forKey: request.url!.absoluteString)
    XCTAssertFalse(cached)
    XCTAssertNil(memory.image(forKey: request.url!.absoluteString))
  }

  @MainActor
  func testCancellingDuringDecodeDoesNotPersistBytes() async throws {
    let url = URL(string: "https://images.test/error-page")!
    let original = TestDataCache()
    let decoder = BlockingDecoder()
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Data("<html>404</html>".utf8)]),
      originalDiskCache: original,
      decoders: [decoder]
    )
    let task = Task { try await manager.image(request: URLRequest(url: url)) }
    await decoder.waitUntilStarted()
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch {}
    let cached = await original.containsData(forKey: url.absoluteString)
    XCTAssertFalse(cached)
  }

  @MainActor
  func testCorruptDiskEntryIsRemoved() async throws {
    let url = URL(string: "https://images.test/corrupt")!
    let original = TestDataCache()
    await original.store(Data("junk".utf8), forKey: url.absoluteString)
    let loader = StubLoader([:])
    let manager = SimpleImageManager.test(loader: loader, originalDiskCache: original)
    do { _ = try await manager.image(request: URLRequest(url: url)); XCTFail("Expected decoding failure") } catch {}
    let cached = await original.containsData(forKey: url.absoluteString)
    XCTAssertFalse(cached)
    let requests = await loader.requestCount
    XCTAssertEqual(requests, 0)
  }

  @MainActor
  func testOriginalDiskStoresExactDownloadedBytes() async throws {
    let original = TestDataCache()
    let processed = TestDataCache()
    let url = URL(string: "https://images.test/exact.webp")!
    let manager = SimpleImageManager.test(loader: StubLoader([url: Fixtures.webp]), originalDiskCache: original, processedDiskCache: processed)
    _ = try await manager.image(request: URLRequest(url: url))
    await original.waitForData(forKey: url.absoluteString)
    let stored = await original.data(forKey: url.absoluteString)
    XCTAssertEqual(stored, Fixtures.webp)
    let processedStored = await processed.containsData(forKey: url.absoluteString)
    XCTAssertFalse(processedStored, "Unprocessed images belong in the original disk cache only")
  }

  @MainActor
  func testOriginalDiskHitDecodesWithoutLoaderAndPopulatesMemory() async throws {
    let url = URL(string: "https://images.test/disk.webp")!
    let original = TestDataCache()
    await original.store(Fixtures.webp, forKey: url.absoluteString)
    let memory = TestMemoryCache()
    let loader = StubLoader([:])
    let manager = SimpleImageManager.test(loader: loader, memoryCache: memory, originalDiskCache: original)
    let image = try await manager.image(request: URLRequest(url: url))
    XCTAssertEqual((image as? UIImage)?.cgImage?.width, 2)
    let requests = await loader.requestCount
    XCTAssertEqual(requests, 0)
    XCTAssertNotNil(memory.image(forKey: url.absoluteString))
  }

  @MainActor
  func testProcessorReceivesDecodedImageAndResultIsCachedSeparately() async throws {
    let url = URL(string: "https://images.test/processed")!
    let memory = TestMemoryCache()
    let output = Fixtures.image(.green)
    let processor = RecordingProcessor(identifier: "tint", output: output)
    let manager = SimpleImageManager.test(loader: StubLoader([url: Fixtures.png(.red)]), memoryCache: memory)
    let result = try await manager.image(request: URLRequest(url: url), processors: [processor])
    let request = SimpleImageRequest(urlRequest: URLRequest(url: url), processors: [processor])
    XCTAssertTrue(result as? UIImage === output)
    XCTAssertTrue(processor.lastInput is UIImage)
    XCTAssertTrue(memory.image(forKey: request.cacheKey) as? UIImage === output)
    XCTAssertNotNil(memory.image(forKey: request.unprocessedCacheKey))
    XCTAssertFalse(memory.image(forKey: request.unprocessedCacheKey) as? UIImage === output)
  }

  @MainActor
  func testProcessedDiskHitSkipsLoaderAndProcessors() async throws {
    let url = URL(string: "https://images.test/processed-disk")!
    let processed = TestDataCache()
    let firstProcessor = RecordingProcessor(identifier: "noop")
    let first = SimpleImageManager.test(loader: StubLoader([url: Fixtures.png()]), processedDiskCache: processed)
    _ = try await first.image(request: URLRequest(url: url), processors: [firstProcessor])
    let cacheKey = SimpleImageRequest(urlRequest: URLRequest(url: url), processors: [firstProcessor]).cacheKey
    await processed.waitForData(forKey: cacheKey)

    let loader = StubLoader([:])
    let secondProcessor = RecordingProcessor(identifier: "noop")
    let second = SimpleImageManager.test(loader: loader, processedDiskCache: processed)
    let image = try await second.image(request: URLRequest(url: url), processors: [secondProcessor])
    XCTAssertTrue(image is UIImage)
    let requests = await loader.requestCount
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(secondProcessor.count, 0)
  }

  @MainActor
  func testCachedImageReturnsMemoryHitSynchronously() async throws {
    let url = URL(string: "https://images.test/sync")!
    let manager = SimpleImageManager.test(loader: StubLoader([url: Fixtures.png()]))
    let request = URLRequest(url: url)
    XCTAssertNil(manager.cachedImage(request: request))
    _ = try await manager.image(request: request)
    XCTAssertNotNil(manager.cachedImage(request: request))
    XCTAssertNil(manager.cachedImage(request: request, processors: [RecordingProcessor()]))
  }

  @MainActor
  func testWebPDecoderKeepsOriginalBytes() async throws {
    let url = URL(string: "https://images.test/original.webp")!
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.webp]),
      decoders: [WebPImageDecoder(), UIImageDecoder()]
    )
    let image = try await manager.image(request: URLRequest(url: url))
    let webp = try XCTUnwrap(image as? WebPImage)
    XCTAssertEqual(webp.originalData, Fixtures.webp)
    XCTAssertEqual(webp.originalFormat, .webp)
    XCTAssertEqual(webp.uiImage.cgImage?.width, 2)
  }

  @MainActor
  func testPassThroughProcessorKeepsWebPBytesOnProcessedDisk() async throws {
    let url = URL(string: "https://images.test/passthrough.webp")!
    let processed = TestDataCache()
    let decoders: [any SimpleImageDecoder] = [WebPImageDecoder(), UIImageDecoder()]
    let processor = RecordingProcessor(identifier: "noop")
    let first = SimpleImageManager.test(loader: StubLoader([url: Fixtures.webp]), processedDiskCache: processed, decoders: decoders)
    _ = try await first.image(request: URLRequest(url: url), processors: [processor])
    let cacheKey = SimpleImageRequest(urlRequest: URLRequest(url: url), processors: [processor]).cacheKey
    await processed.waitForData(forKey: cacheKey)
    let stored = await processed.data(forKey: cacheKey)
    XCTAssertEqual(stored, Fixtures.webp)

    let second = SimpleImageManager.test(loader: StubLoader([:]), processedDiskCache: processed, decoders: decoders)
    let image = try await second.image(request: URLRequest(url: url), processors: [RecordingProcessor(identifier: "noop")])
    XCTAssertEqual((image as? WebPImage)?.originalData, Fixtures.webp)
  }

  @MainActor
  func testPixelProcessorDropsWebPBytes() async throws {
    let url = URL(string: "https://images.test/blurred.webp")!
    let processed = TestDataCache()
    let processor = PixelProcessor()
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.webp]),
      processedDiskCache: processed,
      decoders: [WebPImageDecoder(), UIImageDecoder()]
    )
    let image = try await manager.image(request: URLRequest(url: url), processors: [processor])
    XCTAssertTrue(image is UIImage)
    XCTAssertFalse(image is OriginalDataProviding)
    XCTAssertTrue(processor.lastInput is WebPImage)
    let cacheKey = SimpleImageRequest(urlRequest: URLRequest(url: url), processors: [processor]).cacheKey
    await processed.waitForData(forKey: cacheKey)
    let stored = try await XCTUnwrapAsync(await processed.data(forKey: cacheKey))
    XCTAssertEqual(SimpleImageFormat(sniffing: stored), .png)
  }

  @MainActor
  func testImageViewDisplaysUIImageConvertible() async throws {
    let url = URL(string: "https://images.test/view.webp")!
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.webp]),
      decoders: [WebPImageDecoder(), UIImageDecoder()]
    )
    let loaded = try await manager.image(request: URLRequest(url: url))
    let cached = try XCTUnwrap(loaded as? WebPImage)
    let view = UIImageView()
    view.si_setImage(using: manager, request: URLRequest(url: url))
    XCTAssertTrue(view.image === cached.uiImage)
  }

  @MainActor
  func testImageViewReuseAndCancellationKeepCurrentPlaceholder() async throws {
    let loader = ControlledLoader()
    let manager = SimpleImageManager.test(loader: loader)
    let view = UIImageView()
    let first = URLRequest(url: URL(string: "https://images.test/first")!)
    let second = URLRequest(url: URL(string: "https://images.test/second")!)
    let placeholder = Fixtures.image(.green)
    view.si_setImage(using: manager, request: first, placeholderImage: Fixtures.image(.red))
    await loader.waitForRequests(1)
    view.si_setImage(using: manager, request: second, placeholderImage: placeholder)
    XCTAssertTrue(view.image === placeholder)
    await loader.waitForRequests(2)
    await loader.waitForCancellations(1)
    view.si_cancelImageDownload()
    await loader.waitForCancellations(2)
    XCTAssertNil(view.si_currentTask)
    XCTAssertTrue(view.image === placeholder)
  }

  @MainActor
  func testImageViewAssignsSuccessfulResult() async throws {
    let loader = ControlledLoader()
    let manager = SimpleImageManager.test(loader: loader)
    let view = UIImageView()
    let request = URLRequest(url: URL(string: "https://images.test/view")!)
    let expected = Fixtures.png(.blue)
    view.si_setImage(using: manager, request: request)
    await loader.waitForRequests(1)
    await loader.finish(request.url!, with: expected)
    let completed = expectation(description: "Image assigned")
    Task { @MainActor in
      while view.si_currentTask != nil { await Task.yield() }
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 3)
    XCTAssertNotNil(view.image)
    XCTAssertEqual(view.image?.pngData(), UIImage(data: expected)?.pngData())
  }

  @MainActor
  func testImageViewUsesMemoryHitWithoutPlaceholder() async throws {
    let url = URL(string: "https://images.test/view-sync")!
    let manager = SimpleImageManager.test(loader: StubLoader([url: Fixtures.png()]))
    let cached = try await manager.image(request: URLRequest(url: url))
    let view = UIImageView()
    view.si_setImage(using: manager, request: URLRequest(url: url), placeholderImage: Fixtures.image(.green))
    XCTAssertTrue(view.image === cached as? UIImage)
    XCTAssertNil(view.si_currentTask)
  }

  @MainActor
  func testDiskAndMemoryCachesRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let disk = SimpleImageDiskCache(dataCache: try DataCache(path: directory))
    try await disk.store(Fixtures.webp, forKey: "cover")
    let stored = try await disk.data(forKey: "cover")
    XCTAssertEqual(stored, Fixtures.webp)
    try await disk.removeData(forKey: "cover")
    let contained = await disk.containsData(forKey: "cover")
    XCTAssertFalse(contained)

    let memory = SimpleImageMemoryCache(imageCache: .init())
    let image = Fixtures.image()
    memory.store(image, forKey: "cover")
    XCTAssertTrue(memory.image(forKey: "cover") as? UIImage === image)
    memory.removeImage(forKey: "cover")
    XCTAssertNil(memory.image(forKey: "cover"))
  }
}
