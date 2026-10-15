//
//  SimpleImageProcessor.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//

import Foundation

/// Transforms a processed image, e.g. resizing or blurring it.
///
/// - Read pixels through `UIImageConvertible`, which `UIImage` and the bundled
///   wrappers (`WebPImage`, animated GIF images) adopt.
/// - When pixels change, return a new representation (typically `UIImage`). Its
///   original bytes (`OriginalDataProviding`) are dropped, and the processed disk
///   cache stores whatever the registered decoders encode for it.
/// - To keep an animation intact, return image types you don't handle unchanged.
public protocol SimpleImageProcessor: Sendable {
  var identifier: String { get }
  
  func process(image: any ProcessedImage) async throws -> any ProcessedImage
}
