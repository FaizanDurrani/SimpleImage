//
//  SimpleImageFormat.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 15/10/2026.
//

import Foundation

public struct SimpleImageFormat: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
  
  public static let jpeg = SimpleImageFormat(rawValue: "jpeg")
  public static let png = SimpleImageFormat(rawValue: "png")
  public static let gif = SimpleImageFormat(rawValue: "gif")
  public static let webp = SimpleImageFormat(rawValue: "webp")
  public static let heic = SimpleImageFormat(rawValue: "heic")
  public static let avif = SimpleImageFormat(rawValue: "avif")
  public static let unknown = SimpleImageFormat(rawValue: "unknown")
  
  /// Determines the format from the leading magic bytes of `data`.
  public init(sniffing data: Data) {
    let bytes = [UInt8](data.prefix(64))
    
    func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
      bytes.count >= offset + signature.count && Array(bytes[offset..<offset + signature.count]) == signature
    }
    
    if matches([0xFF, 0xD8, 0xFF]) {
      self = .jpeg
    } else if matches([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      self = .png
    } else if matches(Array("GIF8".utf8)) {
      self = .gif
    } else if matches(Array("RIFF".utf8)) && matches(Array("WEBP".utf8), at: 8) {
      self = .webp
    } else if matches(Array("ftyp".utf8), at: 4) {
      self = Self.isoMediaFormat(bytes)
    } else {
      self = .unknown
    }
  }
  
  /// Reads the major and compatible brands of an ISO-BMFF `ftyp` box.
  private static func isoMediaFormat(_ bytes: [UInt8]) -> SimpleImageFormat {
    let boxSize = bytes.prefix(4).reduce(0) { $0 << 8 | Int($1) }
    let boxEnd = min(max(boxSize, 16), bytes.count)
    
    var brands: [String] = []
    if bytes.count >= 12 {
      brands.append(String(decoding: bytes[8..<12], as: UTF8.self))
    }
    var offset = 16
    while offset + 4 <= boxEnd {
      brands.append(String(decoding: bytes[offset..<offset + 4], as: UTF8.self))
      offset += 4
    }
    
    if brands.contains(where: { ["avif", "avis"].contains($0) }) {
      return .avif
    }
    if brands.contains(where: { ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains($0) }) {
      return .heic
    }
    return .unknown
  }
}
