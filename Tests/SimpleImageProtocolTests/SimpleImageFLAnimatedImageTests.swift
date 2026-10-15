import FLAnimatedImage
import Foundation
import XCTest
@testable import SimpleImage
import SimpleImageFLAnimatedImage
import SimpleImageUIKit
import UIKit

final class SimpleImageFLAnimatedImageTests: XCTestCase, @unchecked Sendable {
  @MainActor
  func testDecodesGIFIntoAnimatedImage() async throws {
    let gif = Fixtures.gif()
    let image = try await FLAnimatedImageDecoder().decode(rawImage: RawImage(data: gif))
    let animated = try XCTUnwrap(image as? FLAnimatedProcessedImage)
    XCTAssertEqual(animated.animatedImage.frameCount, 2)
    XCTAssertEqual(animated.originalData, gif)
    XCTAssertEqual(animated.originalFormat, .gif)
    XCTAssertTrue(animated.uiImage === animated.animatedImage.posterImage)
    XCTAssertGreaterThanOrEqual(animated.cost, gif.count + Int(animated.animatedImage.frameCount) * animated.uiImage.cost)
  }

  @MainActor
  func testPixelProcessorTurnsAnimatedImageIntoStillImage() async throws {
    let url = URL(string: "https://images.test/processed.gif")!
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.gif()]),
      decoders: [FLAnimatedImageDecoder(), UIImageDecoder()]
    )
    let image = try await manager.image(request: URLRequest(url: url), processors: [PixelProcessor()])
    XCTAssertTrue(image is UIImage)
  }

  @MainActor
  func testProcessedDataRoutesBackToAnimatedDecoderBySniffing() async throws {
    let decoders: [any SimpleImageDecoder] = [FLAnimatedImageDecoder(), UIImageDecoder()]
    let animated = try await decoders.decode(rawImage: RawImage(data: Fixtures.gif()))
    let encoded = try XCTUnwrap(decoders.encode(processedImage: animated))
    XCTAssertEqual(SimpleImageFormat(sniffing: encoded), .gif)
    let decoded = try await decoders.decode(processedImageData: encoded)
    XCTAssertEqual((decoded as? FLAnimatedProcessedImage)?.animatedImage.frameCount, 2)
  }

  @MainActor
  func testNonGIFFallsBackToUIImageDecoder() async throws {
    let url = URL(string: "https://images.test/still.png")!
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.png()]),
      decoders: [FLAnimatedImageDecoder(), UIImageDecoder()]
    )
    let image = try await manager.image(request: URLRequest(url: url))
    XCTAssertTrue(image is UIImage)
  }

  @MainActor
  func testImageViewDisplaysAnimatedImage() async throws {
    let url = URL(string: "https://images.test/animated.gif")!
    let manager = SimpleImageManager.test(
      loader: StubLoader([url: Fixtures.gif()]),
      decoders: [FLAnimatedImageDecoder(), UIImageDecoder()]
    )
    let view = FLAnimatedImageView()
    view.si_setImage(using: manager, request: URLRequest(url: url))
    let displayed = expectation(description: "Animated image assigned")
    Task { @MainActor in
      while view.animatedImage == nil { await Task.yield() }
      displayed.fulfill()
    }
    await fulfillment(of: [displayed], timeout: 3)
    XCTAssertEqual(view.animatedImage?.frameCount, 2)

    // A memory hit for a still image replaces the animation synchronously.
    let stillURL = URL(string: "https://images.test/still.png")!
    let stillManager = SimpleImageManager.test(loader: StubLoader([stillURL: Fixtures.png()]))
    let still = try await stillManager.image(request: URLRequest(url: stillURL))
    view.si_setImage(using: stillManager, request: URLRequest(url: stillURL))
    XCTAssertNil(view.animatedImage)
    XCTAssertTrue(view.image === still as? UIImage)
  }
}
