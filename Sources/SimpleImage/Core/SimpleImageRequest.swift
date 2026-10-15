//
//  SimpleImageRequest.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

public struct SimpleImageRequest: Sendable, Equatable {
  public let urlRequest: URLRequest
  public let processors: [any SimpleImageProcessor]
  public let unprocessedCacheKey: String
  public let cacheKey: String
  
  public init(
    urlRequest: URLRequest,
    processors: [any SimpleImageProcessor],
  ) {
    self.urlRequest = urlRequest
    self.processors = processors
    
    self.unprocessedCacheKey = urlRequest.url!.absoluteString
    
    if processors.isEmpty {
      self.cacheKey = self.unprocessedCacheKey
    } else {
      let processorIdentifier = processors.lazy.map { "\($0.identifier)" }.joined(separator: "-")
      self.cacheKey = "\(urlRequest.url!.absoluteString)--\(processorIdentifier)"
    }
  }
  
  public static func == (lhs: SimpleImageRequest, rhs: SimpleImageRequest) -> Bool {
    lhs.urlRequest == rhs.urlRequest && lhs.cacheKey == rhs.cacheKey && lhs.unprocessedCacheKey == rhs.unprocessedCacheKey
  }
}
