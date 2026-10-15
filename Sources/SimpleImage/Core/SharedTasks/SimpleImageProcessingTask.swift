//
//  SimpleImageProcessingTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

/// Applies the request's processors and caches the result.
final class SimpleImageProcessingTask: SimpleImageSharedTask, @unchecked Sendable {
  init(
    imageRequest: SimpleImageRequest,
    image: any ProcessedImage,
    decoders: [any SimpleImageDecoder],
    memoryCache: SimpleImageMemoryCaching,
    processedDiskCache: SimpleImageDataCaching,
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    super.init(request: imageRequest.urlRequest, onFinish: onFinish)
    
    self.state = .waiting { [weak self] in
      guard let self else { return }
      
      do {
        var image = image
        
        for processor in imageRequest.processors {
          try Task.checkCancellation()
          image = try await processor.process(image: image)
        }
        
        memoryCache.store(image, forKey: imageRequest.cacheKey)
        self.finish(with: .success(.image(image)))
        
        // Persist after delivering; the memory cache serves requests meanwhile.
        if let data = decoders.encode(processedImage: image) {
          try? await processedDiskCache.store(data, forKey: imageRequest.cacheKey)
        }
      } catch {
        self.finish(with: .failure(error))
      }
    }
  }
}
