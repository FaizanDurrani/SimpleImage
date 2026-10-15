//
//  SimpleImageMemoryCache.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation
import SimpleImage

public final class SimpleImageMemoryCache: SimpleImageMemoryCaching {
  public let imageCache: ImageCache
  
  public init(imageCache: ImageCache) {
    self.imageCache = imageCache
  }
  
  public func image(forKey cacheKey: String) -> (any ProcessedImage)? {
    self.imageCache[cacheKey]
  }
  
  public func store(_ image: any ProcessedImage, forKey cacheKey: String) {
    self.imageCache[cacheKey] = image
  }
  
  public func removeImage(forKey cacheKey: String) {
    self.imageCache[cacheKey] = nil
  }
}
