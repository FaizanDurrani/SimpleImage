//
//  SimpleImageManager.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation

public enum SimpleImageError: Error {
  case invalidImageData
  case cacheMiss(cacheKey: String)
}

public final class SimpleImageManager: Sendable, Hashable {
  public static func == (lhs: SimpleImageManager, rhs: SimpleImageManager) -> Bool { lhs === rhs }
  public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

  public let imageLoader: SimpleImageLoader
  public let memoryCache: SimpleImageMemoryCaching
  public let originalDiskCache: SimpleImageDataCaching
  public let processedDiskCache: SimpleImageDataCaching
  public let decoders: [any SimpleImageDecoder]
  public let imageTransformers: [SimpleImageTransformer]
  
  private let processedCacheTasks = SimpleImageSharedTaskRegistry<SimpleImageCacheTask>()
  private let downloadTasks = SimpleImageSharedTaskRegistry<SimpleImageDownloadTask>()
  private let decodingTasks = SimpleImageSharedTaskRegistry<SimpleImageDecodingTask>()
  private let processingTasks = SimpleImageSharedTaskRegistry<SimpleImageProcessingTask>()
  
  /// - Parameters:
  ///   - memoryCache: Holds processed, ready to display images.
  ///   - originalDiskCache: Holds the original bytes returned by requests.
  ///   - processedDiskCache: Holds encoded results of processors. Use a different store than `originalDiskCache`.
  ///   - decoders: Tried in order for each image format; put specialised decoders before `UIImageDecoder`,
  ///     e.g. `[WebPImageDecoder(), UIImageDecoder()]` to keep the original WebP bytes.
  public init(
    imageLoader: SimpleImageLoader,
    memoryCache: SimpleImageMemoryCaching,
    originalDiskCache: SimpleImageDataCaching,
    processedDiskCache: SimpleImageDataCaching,
    decoders: [any SimpleImageDecoder] = [UIImageDecoder()],
    imageTransformers: [SimpleImageTransformer] = []
  ) {
    self.imageLoader = imageLoader
    self.memoryCache = memoryCache
    self.originalDiskCache = originalDiskCache
    self.processedDiskCache = processedDiskCache
    self.decoders = decoders
    self.imageTransformers = imageTransformers
  }
  
  public typealias CompletionHandler = @Sendable @MainActor (Result<any ProcessedImage, Error>) -> Void
  public typealias ProgressHandler = @Sendable (Double) -> Void

  /// Returns the processed image for the request if it's in the memory cache.
  public func cachedImage(
    request: URLRequest,
    processors: [any SimpleImageProcessor] = []
  ) -> (any ProcessedImage)? {
    self.memoryCache.image(
      forKey: SimpleImageRequest(
        urlRequest: request,
        processors: processors
      ).cacheKey
    )
  }

  @discardableResult
  public func retrieveImage(
    request: URLRequest,
    processors: [any SimpleImageProcessor] = [],
    progressHandler: ProgressHandler? = nil,
    completion: @escaping CompletionHandler
  ) -> SimpleImageTask {
    retrieveImage(
      imageRequest: SimpleImageRequest(urlRequest: request, processors: processors),
      progressHandler: progressHandler,
      completion: completion
    )
  }

  @discardableResult
  public func retrieveImage(
    imageRequest: SimpleImageRequest,
    progressHandler: ProgressHandler? = nil,
    completion: @escaping CompletionHandler
  ) -> SimpleImageTask {
    SimpleImageTask(
      imageRequest: imageRequest,
      imageManager: self,
      progressHandler: progressHandler,
      completionHandler: { _, result in
        let result = result.flatMap { output -> Result<any ProcessedImage, Error> in
          guard case .image(let image) = output else { return .failure(SimpleImageError.invalidImageData) }
          return .success(image)
        }
        Task { @MainActor in completion(result) }
      }
    )
  }

  public func image(
    request: URLRequest,
    processors: [any SimpleImageProcessor] = [],
    progressHandler: ProgressHandler? = nil
  ) async throws -> any ProcessedImage {
    let cancellation = ImageTaskCancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let task = retrieveImage(
          request: request,
          processors: processors,
          progressHandler: progressHandler,
          completion: { continuation.resume(with: $0) }
        )
        cancellation.install(task)
      }
    } onCancel: {
      cancellation.cancel()
    }
  }

  func processedCacheTask(request: SimpleImageRequest) -> SimpleImageCacheTask {
    self.processedCacheTasks.task(forKey: request.cacheKey) { onFinish in
      SimpleImageCacheTask(
        imageRequest: request,
        processedDiskCache: self.processedDiskCache,
        memoryCache: self.memoryCache,
        decoders: self.decoders,
        onFinish: onFinish
      )
    }
  }
  
  func downloadTask(request: SimpleImageRequest) -> SimpleImageDownloadTask {
    self.downloadTasks.task(forKey: request.unprocessedCacheKey) { onFinish in
      SimpleImageDownloadTask(
        imageRequest: request,
        imageLoader: self.imageLoader,
        imageTransformers: self.imageTransformers,
        originalDiskCache: self.originalDiskCache,
        onFinish: onFinish
      )
    }
  }
  
  func decodingTask(request: SimpleImageRequest, rawImage: RawImage, isFromDiskCache: Bool) -> SimpleImageDecodingTask {
    self.decodingTasks.task(forKey: request.unprocessedCacheKey) { onFinish in
      SimpleImageDecodingTask(
        imageRequest: request,
        rawImage: rawImage,
        isFromDiskCache: isFromDiskCache,
        decoders: self.decoders,
        memoryCache: self.memoryCache,
        originalDiskCache: self.originalDiskCache,
        onFinish: onFinish
      )
    }
  }
  
  func processingTask(request: SimpleImageRequest, image: any ProcessedImage) -> SimpleImageProcessingTask {
    self.processingTasks.task(forKey: request.cacheKey) { onFinish in
      SimpleImageProcessingTask(
        imageRequest: request,
        image: image,
        decoders: self.decoders,
        memoryCache: self.memoryCache,
        processedDiskCache: self.processedDiskCache,
        onFinish: onFinish
      )
    }
  }
}

private final class ImageTaskCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var task: SimpleImageTask?
  private var cancelled = false

  func install(_ task: SimpleImageTask) {
    let shouldCancel = lock.withLock {
      if cancelled { return true }
      self.task = task
      return false
    }
    if shouldCancel { task.cancel() }
  }

  func cancel() {
    let task = lock.withLock {
      cancelled = true
      let task = self.task
      self.task = nil
      return task
    }
    task?.cancel()
  }
}
