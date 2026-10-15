//
//  SimpleImageDecodingTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//


import Foundation

/// Decodes original image bytes into a ready to display image, persisting
/// network bytes to the original disk cache only once they decode.
final class SimpleImageDecodingTask: SimpleImageSharedTask, @unchecked Sendable {
  init(
    imageRequest: SimpleImageRequest,
    rawImage: RawImage,
    isFromDiskCache: Bool,
    decoders: [any SimpleImageDecoder],
    memoryCache: SimpleImageMemoryCaching,
    originalDiskCache: SimpleImageDataCaching,
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    super.init(request: imageRequest.urlRequest, onFinish: onFinish)
    
    self.state = .waiting { [weak self] in
      guard let self else { return }
      
      do {
        let image = try await decoders.decode(rawImage: rawImage)
        
        memoryCache.store(image, forKey: imageRequest.unprocessedCacheKey)
        self.finish(with: .success(.image(image)))
        
        // Persist after delivering; the memory cache serves requests meanwhile.
        if !isFromDiskCache {
          try? await originalDiskCache.store(rawImage.data, forKey: imageRequest.unprocessedCacheKey)
        }
      } catch {
        if isFromDiskCache && !(error is CancellationError) {
          // Bytes no decoder understands shouldn't keep being served from disk.
          try? await originalDiskCache.removeData(forKey: imageRequest.unprocessedCacheKey)
        }
        
        self.finish(with: .failure(error))
      }
    }
  }
}
