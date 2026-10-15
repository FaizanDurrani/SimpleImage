//
//  FLAnimatedImageView+SimpleImage.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import FLAnimatedImage
import Foundation
import SimpleImage
import SimpleImageUIKit
import UIKit

extension FLAnimatedImageView: SimpleImageDisplaying {
  public func si_display(_ image: any ProcessedImage) {
    if let animatedImage = image as? FLAnimatedProcessedImage {
      self.animatedImage = animatedImage.animatedImage
    } else if let image = image as? UIImageConvertible {
      self.animatedImage = nil
      self.image = image.uiImage
    }
  }
  
  public func si_prepareForNewImage() {
    self.animatedImage = nil
  }
}
