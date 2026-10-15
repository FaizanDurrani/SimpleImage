//
//  FLAnimatedImageDecoder.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import FLAnimatedImage
import Foundation
import SimpleImage

/// Decodes GIFs into `FLAnimatedProcessedImage`. Register before `UIImageDecoder`.
public struct FLAnimatedImageDecoder: SimpleImageDecoder {
  public init() {}
  
  public func canDecode(_ format: SimpleImageFormat) -> Bool {
    format == .gif
  }
  
  public func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    try await self.decode(data: rawImage.data)
  }
  
  public func encode(processedImage: any ProcessedImage) -> Data? {
    (processedImage as? FLAnimatedProcessedImage)?.originalData
  }
  
  @concurrent private func decode(data: Data) async throws -> FLAnimatedProcessedImage {
    try Task.checkCancellation()
    guard let animatedImage = FLAnimatedImage(animatedGIFData: data) else {
      throw SimpleImageError.invalidImageData
    }
    
    return FLAnimatedProcessedImage(animatedImage: animatedImage)
  }
}
