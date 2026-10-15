//
//  SimpleImageDecoder.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation

public protocol SimpleImageDecoder: Sendable {
  func canDecode(_ format: SimpleImageFormat) -> Bool
  
  func decode(rawImage: RawImage) async throws -> any ProcessedImage
  
  /// Encodes a processed image for the processed disk cache, or returns `nil`
  /// when this decoder doesn't handle the image's type. The encoded bytes must
  /// sniff to a format this decoder `canDecode`.
  func encode(processedImage: any ProcessedImage) -> Data?
  
  /// Decodes bytes produced by `encode(processedImage:)`. Defaults to
  /// `decode(rawImage:)`, for decoders whose encoded form is a regular image file.
  func decode(processedImageData: Data) async throws -> any ProcessedImage
}

extension SimpleImageDecoder {
  public func decode(processedImageData: Data) async throws -> any ProcessedImage {
    try await self.decode(rawImage: RawImage(data: processedImageData))
  }
}

extension [any SimpleImageDecoder] {
  func decode(rawImage: RawImage) async throws -> any ProcessedImage {
    try await self.decode(format: rawImage.format) { try await $0.decode(rawImage: rawImage) }
  }
  
  func decode(processedImageData data: Data) async throws -> any ProcessedImage {
    try await self.decode(format: SimpleImageFormat(sniffing: data)) { try await $0.decode(processedImageData: data) }
  }
  
  func encode(processedImage: any ProcessedImage) -> Data? {
    self.lazy.compactMap { $0.encode(processedImage: processedImage) }.first
  }
  
  /// Tries each decoder that supports `format`, in order, returning the first success.
  private func decode(
    format: SimpleImageFormat,
    using decode: (any SimpleImageDecoder) async throws -> any ProcessedImage
  ) async throws -> any ProcessedImage {
    var lastError: Error = SimpleImageError.invalidImageData
    
    for decoder in self where decoder.canDecode(format) {
      try Task.checkCancellation()
      do {
        return try await decode(decoder)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        lastError = error
      }
    }
    
    throw lastError
  }
}
