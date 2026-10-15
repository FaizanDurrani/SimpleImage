//
//  SimpleImageCache.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation

/// Holds processed, ready to display images.
public protocol SimpleImageMemoryCaching: Sendable {
  func image(forKey cacheKey: String) -> (any ProcessedImage)?
  
  func store(_ image: any ProcessedImage, forKey cacheKey: String)
  
  func removeImage(forKey cacheKey: String)
}

/// Holds encoded image bytes, used for both original and processed disk caches.
public protocol SimpleImageDataCaching: Sendable {
  func data(forKey cacheKey: String) async throws -> Data?
  
  func store(_ data: Data, forKey cacheKey: String) async throws
  
  func removeData(forKey cacheKey: String) async throws
  
  func containsData(forKey cacheKey: String) async -> Bool
}
