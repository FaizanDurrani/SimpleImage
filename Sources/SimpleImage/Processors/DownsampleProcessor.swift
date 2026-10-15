//
//  DownsampleProcessor.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 16/10/2026.
//

import Foundation
import ImageIO
import UIKit

/// Downscales images to at most `maxPixelWidth` pixels wide, keeping the aspect ratio.
///
/// From encoded bytes, ImageIO decodes straight to the target size, so the
/// full-size bitmap never exists. Images already narrow enough decode normally.
/// Animated images become a still of their first frame.
public struct DownsampleProcessor: SimpleImageDataProcessor {
  public let maxPixelWidth: Int

  public var identifier: String { "downsample-\(self.maxPixelWidth)" }

  public init(maxPixelWidth: Int) {
    precondition(maxPixelWidth > 0, "maxPixelWidth must be positive")
    self.maxPixelWidth = maxPixelWidth
  }

  @concurrent public func process(rawImage: RawImage) async throws -> (any ProcessedImage)? {
    try Task.checkCancellation()

    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard
      let source = CGImageSourceCreateWithData(rawImage.data as CFData, sourceOptions),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else {
      return nil
    }

    // EXIF orientations 5–8 rotate the image by 90°, swapping its displayed width and height.
    let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
    let (displayWidth, displayHeight) = orientation >= 5 ? (height, width) : (width, height)
    guard displayWidth > self.maxPixelWidth else { return nil }

    // ImageIO bounds the longer side, so scale it by the same ratio as the width.
    let maxPixelSize = (Double(self.maxPixelWidth) * Double(max(displayWidth, displayHeight)) / Double(displayWidth)).rounded(.up)
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary

    try Task.checkCancellation()
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    let image = UIImage(cgImage: thumbnail)
    return await image.byPreparingForDisplay() ?? image
  }

  public func process(image: any ProcessedImage) async throws -> any ProcessedImage {
    guard let uiImage = (image as? UIImageConvertible)?.uiImage else {
      throw SimpleImageError.invalidImageData
    }

    let pixelSize = CGSize(width: uiImage.size.width * uiImage.scale, height: uiImage.size.height * uiImage.scale)
    guard pixelSize.width > CGFloat(self.maxPixelWidth) else { return uiImage }

    try Task.checkCancellation()
    let ratio = CGFloat(self.maxPixelWidth) / pixelSize.width
    let target = CGSize(width: CGFloat(self.maxPixelWidth), height: (pixelSize.height * ratio).rounded())
    return await uiImage.byPreparingThumbnail(ofSize: target) ?? uiImage
  }
}
