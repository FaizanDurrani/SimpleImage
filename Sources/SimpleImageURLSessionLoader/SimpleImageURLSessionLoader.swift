//
//  SimpleImageURLSessionLoader.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation
import SimpleImage

public final class SimpleImageURLSessionLoader: SimpleImageLoader {
  public let urlSession: URLSession
  
  public init(urlSession: URLSession) {
    self.urlSession = urlSession
  }
  
  /// Downloads the response body in the chunks URLSession delivers, reporting
  /// progress in steps of at least 1% when the content length is known.
  @concurrent public func imageData(
    for request: URLRequest,
    progressHandler: @escaping @Sendable (Double) -> Void
  ) async throws -> Data {
    let task = self.urlSession.dataTask(with: request)
    let delegate = DataTaskDelegate(progressHandler: progressHandler)
    task.delegate = delegate
    
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        delegate.start(task, continuation: continuation)
      }
    } onCancel: {
      task.cancel()
    }
  }
}

private final class DataTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private static let progressStep = 0.01
  
  private let lock = NSLock()
  private let progressHandler: @Sendable (Double) -> Void
  private var continuation: CheckedContinuation<Data, Error>?
  private var data = Data()
  private var reportedFraction = 0.0
  
  init(progressHandler: @escaping @Sendable (Double) -> Void) {
    self.progressHandler = progressHandler
  }
  
  func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Data, Error>) {
    self.lock.withLock { self.continuation = continuation }
    self.progressHandler(0)
    task.resume()
  }
  
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let expectedLength = dataTask.countOfBytesExpectedToReceive
    
    let fraction: Double? = self.lock.withLock {
      if self.data.isEmpty, expectedLength > 0 {
        self.data.reserveCapacity(Int(expectedLength))
      }
      self.data.append(data)
      
      guard expectedLength > 0 else { return nil }
      let fraction = min(1, Double(self.data.count) / Double(expectedLength))
      guard fraction - self.reportedFraction >= Self.progressStep else { return nil }
      
      self.reportedFraction = fraction
      return fraction
    }
    
    if let fraction { self.progressHandler(fraction) }
  }
  
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let (continuation, data, reportedFraction) = self.lock.withLock {
      defer { self.continuation = nil }
      return (self.continuation, self.data, self.reportedFraction)
    }
    
    if let error {
      let isCancelled = (error as? URLError)?.code == .cancelled
      continuation?.resume(throwing: isCancelled ? CancellationError() : error)
    } else {
      if reportedFraction < 1 { self.progressHandler(1) }
      continuation?.resume(returning: data)
    }
  }
}
