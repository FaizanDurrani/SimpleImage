//
//  RawImage.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation

/// The bytes returned by an image request, after transformers, in their original format.
public struct RawImage: Sendable, Equatable {
  public let data: Data
  public let format: SimpleImageFormat
  
  public init(data: Data, format: SimpleImageFormat) {
    self.data = data
    self.format = format
  }
  
  public init(data: Data) {
    self.init(data: data, format: SimpleImageFormat(sniffing: data))
  }
}
