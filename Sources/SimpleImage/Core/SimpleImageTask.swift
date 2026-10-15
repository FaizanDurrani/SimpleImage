//
//  SimpleImageTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

public final class SimpleImageTask: Sendable {
  enum Stage {
    case processedCache
    case download
    case decoding
    case processing
  }
  
  enum State {
    case initialising
    case running(Stage, SimpleImageSharedTask)
    case cancelled
    case finished
  }
  
  public let id: UUID
  public let imageRequest: SimpleImageRequest
  
  public var isCancelled: Bool {
    self.lock.withLock {
      if case .cancelled = self.state { return true }
      return false
    }
  }
  
  private let imageManager: SimpleImageManager?
  private nonisolated(unsafe) var state: State
  
  private let completionHandler: @Sendable (SimpleImageTask, Result<SimpleImageStageOutput, Error>) -> Void
  private let lock = NSLock()
  private let progressHandler: SimpleImageManager.ProgressHandler?
  
  init(
    imageRequest: SimpleImageRequest,
    imageManager: SimpleImageManager,
    progressHandler: SimpleImageManager.ProgressHandler?,
    completionHandler: @escaping @Sendable (SimpleImageTask, Result<SimpleImageStageOutput, Error>) -> Void
  ) {
    self.progressHandler = progressHandler
    self.id = UUID()
    self.imageRequest = imageRequest
    self.imageManager = imageManager
    self.state = .initialising
    self.completionHandler = completionHandler
    
    self.beginImageLoading()
  }
  
  public func cancel() {
    let previousState = lock.withLock { () -> State? in
      switch state {
      case .cancelled, .finished: return nil
      default:
        let previous = state
        state = .cancelled
        return previous
      }
    }
    guard let previousState else { return }
    if case .running(_, let task) = previousState {
      task.detach(task: self)
    }
    completionHandler(self, .failure(CancellationError()))
  }

  func reportProgress(_ fraction: Double) {
    let active = lock.withLock {
      switch state {
      case .cancelled, .finished: return false
      default: return true
      }
    }
    if active, fraction.isFinite { progressHandler?(min(1, max(0, fraction))) }
  }

  private func beginImageLoading() {
    guard let imageManager else { return }
    
    if let image = imageManager.memoryCache.image(forKey: self.imageRequest.cacheKey) {
      self.finishLoading(with: .success(.image(image)))
    } else if self.imageRequest.processors.isEmpty {
      self.loadImageFromNetwork()
    } else {
      self.run(.processedCache) { imageManager in
        imageManager.processedCacheTask(request: self.imageRequest)
      }
    }
  }
  
  private func loadOriginalImage() {
    guard let imageManager else { return }
    
    if let image = imageManager.memoryCache.image(forKey: self.imageRequest.unprocessedCacheKey) {
      self.processImage(.decoded(image))
    } else {
      self.loadImageFromNetwork()
    }
  }
  
  private func loadImageFromNetwork() {
    self.run(.download) { imageManager in
      imageManager.downloadTask(request: self.imageRequest)
    }
  }
  
  private func decodeImage(_ rawImage: RawImage, isFromDiskCache: Bool) {
    self.run(.decoding) { imageManager in
      imageManager.decodingTask(request: self.imageRequest, rawImage: rawImage, isFromDiskCache: isFromDiskCache)
    }
  }
  
  private func processImage(_ input: SimpleImageProcessingInput) {
    self.run(.processing) { imageManager in
      imageManager.processingTask(request: self.imageRequest, input: input)
    }
  }
  
  /// Installs and attaches to the shared task for `stage`, retrying if the
  /// shared task was cancelled by its last subscriber in the meantime.
  private func run(_ stage: Stage, makeTask: (SimpleImageManager) -> SimpleImageSharedTask) {
    guard let imageManager else { return }
    
    let internalTask = makeTask(imageManager)
    let installed: Bool
    
    self.lock.lock()
    switch self.state {
      case .running(_, let currentTask) where currentTask === internalTask:
        installed = false
        
      case .initialising, .running:
        self.state = .running(stage, internalTask)
        installed = true
        
      case .cancelled, .finished:
        installed = false
    }
    self.lock.unlock()
    
    guard installed else {
      internalTask.detach(task: self)
      return
    }
    
    switch internalTask.attach(task: self) {
      case .attached:
        let isStillCurrent = self.lock.withLock {
          if case .running(_, let currentTask) = self.state, currentTask === internalTask {
            return true
          }
          
          return false
        }

        if !isStillCurrent {
          internalTask.detach(task: self)
        }
        
      case .finished(let result):
        self.processStageResult(result, from: internalTask)
        
      case .cancelled:
        self.run(stage, makeTask: makeTask)
    }
  }
  
  func processStageResult(_ result: Result<SimpleImageStageOutput, Error>, from sharedTask: SimpleImageSharedTask) {
    let stage: Stage? = self.lock.withLock {
      if case .running(let stage, let currentTask) = self.state, currentTask === sharedTask {
        return stage
      }
      
      return nil
    }
    
    guard let stage else { return }
    
    switch (stage, result) {
      case (.processedCache, .failure):
        self.loadOriginalImage()
        
      case (.download, .success(.raw(let rawImage, let isFromDiskCache))):
        if self.imageRequest.processors.first is any SimpleImageDataProcessor {
          // Skip the full-size decode; the processor works from the bytes.
          self.processImage(.raw(rawImage, isFromDiskCache: isFromDiskCache))
        } else {
          self.decodeImage(rawImage, isFromDiskCache: isFromDiskCache)
        }
        
      case (.decoding, .success(.image(let image))) where !self.imageRequest.processors.isEmpty:
        self.processImage(.decoded(image))
        
      case (.decoding, .success(.image(let image))):
        // Only originals displayed as-is are memory-cached, so processed requests
        // (e.g. thumbnails) don't fill the cache with full-size images.
        self.imageManager?.memoryCache.store(image, forKey: self.imageRequest.unprocessedCacheKey)
        self.finishLoading(with: result)
        
      default:
        self.finishLoading(with: result)
    }
  }
  
  private func finishLoading(with result: Result<SimpleImageStageOutput, Error>) {
    self.lock.lock()
    switch self.state {
      case .initialising, .running:
        self.state = .finished
        self.lock.unlock()
        
        self.completionHandler(self, result)
      default:
        self.lock.unlock()
    }
  }
}
