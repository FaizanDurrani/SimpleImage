//
//  WebPImageDecoder.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation
import UIKit

/// A decoded WebP that keeps its original bytes.
public struct WebPImage: UIImageConvertible, OriginalDataProviding {
  public let uiImage: UIImage
  public let originalData: Data
  
  public init(uiImage: UIImage, originalData: Data) {
    self.uiImage = uiImage
    self.originalData = originalData
  }
  
  public var cost: Int {
    self.uiImage.cost + self.originalData.count
  }
}

/// Decodes WebP into `WebPImage`, keeping the original bytes for callers and the
/// processed disk cache. Animated WebP decodes to its first frame.
/// Register before `UIImageDecoder`.
public struct WebPImageDecoder: SimpleImageDecoder {
  public init() {}
  
  public func canDecode(_ format: SimpleImageFormat) -> Bool {
    format == .webp
  }
  
  public func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    WebPImage(uiImage: try await UIImageDecoder.decodedImage(from: rawImage.data), originalData: rawImage.data)
  }
  
  public func encode(processedImage: any ProcessedImage) -> Data? {
    (processedImage as? WebPImage)?.originalData
  }
}
