import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders text as a crisp QR code image (generated locally; nothing leaves the Mac).
public enum QRCode {
    public static func image(for text: String, size: CGFloat = 280) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = (size / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1)))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
