//
//  SimpleImageDataProcessor.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 16/10/2026.
//

import Foundation

/// A processor that can produce its output straight from the encoded bytes,
/// skipping a full-size decode (e.g. downsampling with ImageIO).
///
/// Used when it's the first processor of a request whose original isn't
/// already decoded in memory; otherwise `process(image:)` runs as usual.
public protocol SimpleImageDataProcessor: SimpleImageProcessor {
  /// Returns the processed image, or `nil` to decode normally and call `process(image:)`.
  func process(rawImage: RawImage) async throws -> (any ProcessedImage)?
}
