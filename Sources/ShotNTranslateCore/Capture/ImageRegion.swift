import CoreGraphics
import Foundation

/// Geometry for choosing text inside a screenshot.
/// Pixel rectangles use a top-left origin. The screenshot itself is not replaced.
public enum ImageRegionGeometry {
    public static func fullRect(width: Int, height: Int) -> CGRect {
        CGRect(x: 0, y: 0, width: max(width, 0), height: max(height, 0))
    }

    /// Letterboxed frame of the image inside a view. The view origin is the bottom-left.
    public static func displayFrame(imageWidth: Int, imageHeight: Int, in viewSize: CGSize) -> CGRect {
        let imageW = CGFloat(max(imageWidth, 1))
        let imageH = CGFloat(max(imageHeight, 1))
        let viewW = max(viewSize.width, 1)
        let viewH = max(viewSize.height, 1)
        let scale = min(viewW / imageW, viewH / imageH)
        let width = imageW * scale
        let height = imageH * scale
        return CGRect(
            x: (viewW - width) / 2,
            y: (viewH - height) / 2,
            width: width,
            height: height
        )
    }

    /// Maps a drag rectangle in the view to image pixels. Returns nil when it is too small to read.
    public static func pixelRect(
        selection: CGRect,
        displayFrame: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect? {
        guard displayFrame.width > 0, displayFrame.height > 0, imageWidth > 0, imageHeight > 0 else {
            return nil
        }
        let local = selection.intersection(displayFrame)
        guard local.width >= 1, local.height >= 1 else { return nil }
        let imageW = CGFloat(imageWidth)
        let imageH = CGFloat(imageHeight)
        let x = (local.minX - displayFrame.minX) / displayFrame.width * imageW
        let height = local.height / displayFrame.height * imageH
        let y = (displayFrame.maxY - local.maxY) / displayFrame.height * imageH
        let bounds = CGRect(x: 0, y: 0, width: imageW, height: imageH)
        let rect = CGRect(x: x, y: y, width: local.width / displayFrame.width * imageW, height: height)
            .integral
            .intersection(bounds)
        guard rect.width >= 4, rect.height >= 4 else { return nil }
        return rect
    }

    /// Maps a top-left pixel rectangle back onto the view.
    public static func viewRect(
        pixelRect: CGRect,
        displayFrame: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let imageW = CGFloat(max(imageWidth, 1))
        let imageH = CGFloat(max(imageHeight, 1))
        let width = pixelRect.width / imageW * displayFrame.width
        let height = pixelRect.height / imageH * displayFrame.height
        let x = displayFrame.minX + pixelRect.minX / imageW * displayFrame.width
        let y = displayFrame.maxY - pixelRect.minY / imageH * displayFrame.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum ImageRegionCrop {
    /// A temporary image for recognition. The source screenshot is left unchanged.
    public static func recognitionImage(from image: CGImage, pixelRect: CGRect) -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let rect = pixelRect.integral.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1 else { return image }
        if rect.minX <= 1, rect.minY <= 1,
           rect.width >= bounds.width - 1, rect.height >= bounds.height - 1 {
            return image
        }
        // `pixelRect` and CGImage cropping both use a top-left origin.
        return image.cropping(to: rect) ?? image
    }
}
