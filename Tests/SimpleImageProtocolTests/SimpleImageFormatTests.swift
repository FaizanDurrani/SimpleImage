import Foundation
import Testing
@testable import SimpleImage

struct SimpleImageFormatTests {
  private func iso(_ majorBrand: String, compatible: [String] = []) -> Data {
    let brands = ([majorBrand, "\0\0\0\0"] + compatible).flatMap { Array($0.utf8) }
    let size = UInt32(8 + brands.count)
    return Data(withUnsafeBytes(of: size.bigEndian, Array.init) + Array("ftyp".utf8) + brands)
  }

  @Test func sniffsKnownFormats() async throws {
    #expect(SimpleImageFormat(sniffing: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
    #expect(SimpleImageFormat(sniffing: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])) == .png)
    #expect(SimpleImageFormat(sniffing: Data("GIF89a".utf8)) == .gif)
    #expect(SimpleImageFormat(sniffing: Data(base64Encoded: "UklGRiwAAABXRUJQVlA4TB8AAAAvAUAAAB8gEEjeHzqN+RcQFPwf3fxHZA/gBgwR/Q8BAA==")!) == .webp)
    #expect(SimpleImageFormat(sniffing: iso("heic")) == .heic)
    #expect(SimpleImageFormat(sniffing: iso("avif")) == .avif)
    #expect(SimpleImageFormat(sniffing: iso("mif1", compatible: ["avif", "miaf"])) == .avif)
    #expect(SimpleImageFormat(sniffing: iso("mif1", compatible: ["heic"])) == .heic)
  }

  @Test func unknownForUnrecognisedOrShortData() async throws {
    #expect(SimpleImageFormat(sniffing: Data()) == .unknown)
    #expect(SimpleImageFormat(sniffing: Data("RIFF".utf8)) == .unknown)
    #expect(SimpleImageFormat(sniffing: Data("invalid".utf8)) == .unknown)
    #expect(SimpleImageFormat(sniffing: iso("mp42")) == .unknown)
  }

  @Test func rawImageSniffsFormat() async throws {
    #expect(RawImage(data: Data("GIF87a".utf8)).format == .gif)
  }
}
