import UIKit

import ImageIO

enum ImageDownsampler {

    /// Downsample so the longest side is at most `maxPixel`.

    static func image(from data: Data, maxPixel: CGFloat) -> UIImage? {

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let options = [

            kCGImageSourceCreateThumbnailFromImageAlways: true,

            kCGImageSourceShouldCacheImmediately: true,

            kCGImageSourceCreateThumbnailWithTransform: true,

            kCGImageSourceThumbnailMaxPixelSize: maxPixel

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

