//
//  SimpleImageProcessingTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

/// What a processing task starts from.
enum SimpleImageProcessingInput: Sendable {
  /// A decoded original, e.g. from the memory cache.
  case decoded(any ProcessedImage)
  /// Encoded bytes, for requests whose first processor is a `SimpleImageDataProcessor`.
  case raw(RawImage, isFromDiskCache: Bool)
}

final class SimpleImageProcessingTask: SimpleImageSharedTask, @unchecked Sendable {
  init(
    imageRequest: SimpleImageRequest,
    input: SimpleImageProcessingInput,
    decoders: [any SimpleImageDecoder],
    memoryCache: SimpleImageMemoryCaching,
    originalDiskCache: SimpleImageDataCaching,
    processedDiskCache: SimpleImageDataCaching,
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    super.init(request: imageRequest.urlRequest, onFinish: onFinish)
    
    self.state = .waiting { [weak self] in
      guard let self else { return }
      
      do {
        var image: any ProcessedImage
        var processors = imageRequest.processors[...]
        var originalToPersist: Data?
        
        switch input {
          case .decoded(let decoded):
            image = decoded
            
          case .raw(let rawImage, let isFromDiskCache):
            do {
              if let dataProcessor = processors.first as? any SimpleImageDataProcessor,
                 let processed = try await dataProcessor.process(rawImage: rawImage) {
                image = processed
                processors = processors.dropFirst()
              } else {
                image = try await decoders.decode(rawImage: rawImage)
              }
            } catch {
              if isFromDiskCache && !(error is CancellationError) {
                // Bytes no decoder understands shouldn't keep being served from disk.
                try? await originalDiskCache.removeData(forKey: imageRequest.unprocessedCacheKey)
              }
              throw error
            }
            
            if !isFromDiskCache {
              originalToPersist = rawImage.data
            }
        }
        
        for processor in processors {
          try Task.checkCancellation()
          image = try await processor.process(image: image)
        }
        
        try Task.checkCancellation()
        memoryCache.store(image, forKey: imageRequest.cacheKey)
        self.finish(with: .success(.image(image)))
        
        // Persist after delivering; the memory cache serves requests meanwhile.
        if let originalToPersist {
          try? await originalDiskCache.store(originalToPersist, forKey: imageRequest.unprocessedCacheKey)
        }
        if let data = decoders.encode(processedImage: image) {
          try? await processedDiskCache.store(data, forKey: imageRequest.cacheKey)
        }
      } catch {
        self.finish(with: .failure(error))
      }
    }
  }
}
