//
//  SimpleImageDownloadTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

/// Loads the original image bytes from the original disk cache or the network.
/// Network bytes are persisted by `SimpleImageDecodingTask` once they decode.
final class SimpleImageDownloadTask: SimpleImageSharedTask, @unchecked Sendable {
  init(
    imageRequest: SimpleImageRequest,
    imageLoader: SimpleImageLoader,
    imageTransformers: [SimpleImageTransformer],
    originalDiskCache: SimpleImageDataCaching,
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    super.init(request: imageRequest.urlRequest, onFinish: onFinish)
    
    self.state = .waiting { [weak self] in
      guard let self else { return }
      
      do {
        if let data = try? await originalDiskCache.data(forKey: imageRequest.unprocessedCacheKey) {
          self.finish(with: .success(.raw(RawImage(data: data), isFromDiskCache: true)))
          return
        }
        
        var imageData = try await imageLoader.imageData(for: imageRequest.urlRequest, progressHandler: { [weak self] in self?.reportProgress($0) })
        
        for imageTransformer in imageTransformers {
          try Task.checkCancellation()
          imageData = try await imageTransformer.transform(data: imageData)
        }
        
        try Task.checkCancellation()
        self.finish(with: .success(.raw(RawImage(data: imageData), isFromDiskCache: false)))
      } catch {
        self.finish(with: .failure(error))
      }
    }
  }
}
