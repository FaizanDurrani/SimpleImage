//
//  ProcessedImage.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation
import UIKit

/// A decoded image that is ready for display.
public protocol ProcessedImage: Sendable {
  /// Approximate memory footprint in bytes, used by memory caches.
  var cost: Int { get }
}

/// A processed image whose pixels can be read as a `UIImage`, e.g. by processors.
public protocol UIImageConvertible: ProcessedImage {
  var uiImage: UIImage { get }
}

/// A processed image that still carries the bytes it was decoded from.
///
/// Processors that change pixels return a new representation, dropping these bytes.
public protocol OriginalDataProviding: ProcessedImage {
  var originalData: Data { get }
}

extension OriginalDataProviding {
  public var originalFormat: SimpleImageFormat {
    SimpleImageFormat(sniffing: self.originalData)
  }
}

extension UIImage: UIImageConvertible {
  public var uiImage: UIImage { self }
  
  public var cost: Int {
    // bytesPerRow * height gives a rough estimation of how much memory
    // the decoded bitmap uses in bytes.
    guard let cgImage else { return 1 }
    return cgImage.bytesPerRow * cgImage.height
  }
}
