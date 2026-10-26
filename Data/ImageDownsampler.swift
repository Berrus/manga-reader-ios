import UIKit

import ImageIO

enum ImageDownsampler {

    /// Downsample so the longest side is at most `maxPixel`.

    static func image(from data: Data, maxPixel: CGFloat) -> UIImage? {

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        guard maxPixel.isFinite, maxPixel > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0, w.isFinite, h.isFinite else { return nil }
        // Bound the bitmap even for very tall strips or deceptive image dimensions.
        let requested = min(Double(maxPixel), max(w, h))
        let ratio = min(1, requested / max(w, h))
        let pixels = w * h * ratio * ratio
        let budgetScale = pixels > 16_000_000 ? sqrt(16_000_000 / pixels) : 1
        let boundedPixel = max(1, requested * budgetScale)
        let options = [

            kCGImageSourceCreateThumbnailFromImageAlways: true,

            kCGImageSourceShouldCacheImmediately: true,

            kCGImageSourceCreateThumbnailWithTransform: true,

            kCGImageSourceThumbnailMaxPixelSize: boundedPixel

        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        return UIImage(cgImage: cg)

    }

    /// Downsample so the image is at most `width` pixels wide (for tall webtoon strips).

    static func image(from data: Data, fittingWidth width: CGFloat) -> UIImage? {

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),

              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],

              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,

              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,

              w > 0 else { return nil }

        let longest = max(w, h)

        let maxPixel = w > Double(width) ? longest * (Double(width) / w) : longest

        return image(from: data, maxPixel: CGFloat(maxPixel))

    }

}

