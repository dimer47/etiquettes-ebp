import UIKit
import PocketPrinter5890Kit

/// One native-resolution raster is shared by the preview and BLE print job.
enum LabelRenderer {
    static let width = 384
    static let height = 240 // 30 mm at the verified nominal 8 dots/mm
    static let barcodeModuleDots = 3
    static let quietZoneDots = 30 // 10 modules on each side

    static func render(_ label: ProductLabel) throws -> MonochromeBitmap {
        let ean = try EAN13.completed(label.ean)
        guard let price = PriceFormatter.formatted(label.price) else { throw LabelError.invalidPrice }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            draw(label.category, in: CGRect(x: 15, y: 4, width: 354, height: 19), maxSize: 17, bold: false)
            draw(label.shelfReference, in: CGRect(x: 15, y: 24, width: 354, height: 17), maxSize: 14, bold: false)
            draw(label.name, in: CGRect(x: 12, y: 44, width: 360, height: 30), maxSize: 27, bold: true)
            // The barcode is placed separately as exact integer-width modules.
            draw(ean, in: CGRect(x: 12, y: 140, width: 360, height: 17), maxSize: 15, bold: false)
            draw("RÉF : \(label.productReference)", in: CGRect(x: 12, y: 159, width: 360, height: 17), maxSize: 15, bold: false)
            draw("Prix de vente TTC", in: CGRect(x: 12, y: 178, width: 360, height: 21), maxSize: 18, bold: true)
            draw(price, in: CGRect(x: 10, y: 199, width: 364, height: 39), maxSize: 36, bold: true)
        }
        guard let cgImage = image.cgImage else { throw LabelError.rasterFailure }
        // Read through a known RGBA layout; no resizing or interpolation.
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapContext = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LabelError.rasterFailure }
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var black = [Bool](repeating: false, count: width * height)
        for i in black.indices {
            let p = i * 4
            // Hard threshold keeps the printed output strictly black or white.
            black[i] = (Int(rgba[p]) * 299 + Int(rgba[p + 1]) * 587 + Int(rgba[p + 2]) * 114) < 160_000
        }
        let modules = try EAN13.modules(for: ean)
        let barcodeWidth = modules.count * barcodeModuleDots + 2 * quietZoneDots
        let left = (width - barcodeWidth) / 2 + quietZoneDots
        for (index, on) in modules.enumerated() where on {
            for y in 79..<138 {
                for dot in 0..<barcodeModuleDots {
                    black[y * width + left + index * barcodeModuleDots + dot] = true
                }
            }
        }
        return try RasterEncoder.encodeBlackPixels(black, width: width, height: height)
    }

    static func preview(_ bitmap: MonochromeBitmap) -> UIImage? {
        var rgba = [UInt8](repeating: 255, count: bitmap.width * bitmap.height * 4)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let byte = bitmap.bytes[y * bitmap.widthBytes + x / 8]
                let black = byte & UInt8(0x80 >> (x % 8)) != 0
                let offset = (y * bitmap.width + x) * 4
                let value: UInt8 = black ? 0 : 255
                rgba[offset] = value; rgba[offset + 1] = value; rgba[offset + 2] = value
            }
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        guard let image = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: bitmap.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func draw(_ text: String, in rect: CGRect, maxSize: CGFloat, bold: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var size = maxSize
        while size > 10 {
            let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
            if (text as NSString).size(withAttributes: [.font: font]).width <= rect.width { break }
            size -= 1
        }
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
    }
}

enum LabelError: LocalizedError {
    case invalidPrice, rasterFailure
    var errorDescription: String? {
        switch self {
        case .invalidPrice: return "Prix invalide"
        case .rasterFailure: return "Impossible de créer le bitmap"
        }
    }
}
