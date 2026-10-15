//
//  SimpleImageDiskCache.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation
import SimpleImage

/// Stores image bytes verbatim. Use separate instances (directories) for
/// original and processed images.
public final class SimpleImageDiskCache: SimpleImageDataCaching {
  public let dataCache: DataCache
  
  public init(dataCache: DataCache) {
    self.dataCache = dataCache
  }
  
  /// Reads from disk off the caller's actor.
  @concurrent public func data(forKey cacheKey: String) async throws -> Data? {
    self.dataCache.cachedData(for: cacheKey)
  }
  
  public func store(_ data: Data, forKey cacheKey: String) async throws {
    self.dataCache.storeData(data, for: cacheKey)
  }
  
  public func removeData(forKey cacheKey: String) async throws {
    self.dataCache.removeData(for: cacheKey)
  }
  
  @concurrent public func containsData(forKey cacheKey: String) async -> Bool {
    self.dataCache.containsData(for: cacheKey)
  }
}
