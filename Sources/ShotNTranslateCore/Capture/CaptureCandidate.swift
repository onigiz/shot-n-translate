import CoreGraphics
import Foundation

/// Picks a screenshot when several captures of the same region disagree.
/// A flat white window and a flat black permission frame both lack contrast.
/// A real page, light or dark, does not.
public enum CaptureCandidate {
    public static func score(_ image: CGImage) -> Double {
        let contrast = TextRecognizer.contrast(image)
        let bright = TextRecognizer.brightPixelFraction(image)
        if contrast < 0.04 {
            return bright * 0.01
        }
        return contrast + TextRecognizer.meanLuminance(image) * 0.05
    }

    public static func preferred(_ images: [CGImage]) -> CGImage? {
        images.max { score($0) < score($1) }
    }
}
