import SwiftUI
import UIKit

struct CoverReaderTint: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    static func extract(_ data: Data?) -> CoverReaderTint {
        let fallback = CoverReaderTint(red: 0, green: 0, blue: 0)
        guard let data, let image = ImageDownsampler.image(from: data, maxPixel: 32)?.cgImage else { return fallback }
        var pixel = [UInt8](repeating: 0, count: 4)
        let worked = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard worked else { return fallback }
        // Keep the canvas dark so the always-white reader controls remain legible.
        return CoverReaderTint(red: Double(pixel[0]) / 255 * 0.18,
                               green: Double(pixel[1]) / 255 * 0.18,
                               blue: Double(pixel[2]) / 255 * 0.18)
    }
}
