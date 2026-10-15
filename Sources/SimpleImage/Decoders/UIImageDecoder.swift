//
//  UIImageDecoder.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation
import UIKit

/// Decodes any format `UIImage(data:)` supports. Animated formats decode to their first frame.
public struct UIImageDecoder: SimpleImageDecoder {
  public init() {}
  
  public func canDecode(_ format: SimpleImageFormat) -> Bool {
    true
  }
  
  public func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    try await Self.decodedImage(from: rawImage.data)
  }
  
  public func encode(processedImage: any ProcessedImage) -> Data? {
    (processedImage as? UIImage)?.pngData()
  }
  
  /// Decodes `data` with `UIImage(data:)` and prepares it for display, off the caller's actor.
  @concurrent public static func decodedImage(from data: Data) async throws -> UIImage {
    guard let image = UIImage(data: data) else {
      throw SimpleImageError.invalidImageData
    }
    
    return await image.byPreparingForDisplay() ?? image
  }
}
