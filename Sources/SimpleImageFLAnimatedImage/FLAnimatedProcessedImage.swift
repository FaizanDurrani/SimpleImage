//
//  FLAnimatedProcessedImage.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import FLAnimatedImage
import Foundation
import SimpleImage
import UIKit

/// An animated GIF ready to be shown by `FLAnimatedImageView`.
///
/// `FLAnimatedImage` is immutable after initialisation apart from its internal,
/// self-synchronised frame cache, so it is safe to pass between threads.
public struct FLAnimatedProcessedImage: OriginalDataProviding, UIImageConvertible, @unchecked Sendable {
  public let animatedImage: FLAnimatedImage
  
  public init(animatedImage: FLAnimatedImage) {
    self.animatedImage = animatedImage
  }
  
  /// The original GIF bytes.
  public var originalData: Data { self.animatedImage.data ?? Data() }
  
  /// The first frame, for processors and plain image views.
  public var uiImage: UIImage { self.animatedImage.posterImage ?? UIImage() }
  
  public var cost: Int {
    // Upper bound: FLAnimatedImage keeps every predrawn frame of GIFs up to
    // 10 MB decoded for as long as the object lives. GIFs costing more than the
    // memory cache's per-entry limit are re-decoded from disk instead.
    self.originalData.count + self.uiImage.cost * max(1, Int(self.animatedImage.frameCount))
  }
}
