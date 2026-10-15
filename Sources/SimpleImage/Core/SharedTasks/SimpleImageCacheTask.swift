//
//  SimpleImageCacheTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

/// Loads a processed image from the processed disk cache.
final class SimpleImageCacheTask: SimpleImageSharedTask, @unchecked Sendable {
  init(
    imageRequest: SimpleImageRequest,
    processedDiskCache: SimpleImageDataCaching,
    memoryCache: SimpleImageMemoryCaching,
    decoders: [any SimpleImageDecoder],
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    super.init(request: imageRequest.urlRequest, onFinish: onFinish)
    
    self.state = .waiting { [weak self] in
      guard let self else { return }
      
      do {
        guard let data = try? await processedDiskCache.data(forKey: imageRequest.cacheKey) else {
          throw SimpleImageError.cacheMiss(cacheKey: imageRequest.cacheKey)
        }
        
        try Task.checkCancellation()
        let image = try await decoders.decode(processedImageData: data)
        
        memoryCache.store(image, forKey: imageRequest.cacheKey)
        self.finish(with: .success(.image(image)))
      } catch {
        self.finish(with: .failure(error))
      }
    }
  }
}
