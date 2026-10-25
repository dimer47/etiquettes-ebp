import UIKit
import PocketPrinter5890Kit

/// One native-resolution raster is shared by the preview and BLE print job.
enum LabelRenderer {
    static let width = 384
    static let barcodeModuleDots = 3
    static let quietZoneDots = 30 // 10 modules on each side

    /// `scale` dessine la même mise en page plus grande, pour une Brother :
    /// le texte est composé à cette résolution, les modules EAN gardent un
    /// nombre entier de points. À 1, c'est exactement le bitmap de la 5890.
    static func render(_ label: ProductLabel, size: LabelSize = .standard,
                       arrangement: LabelArrangement = .current,
                       scale: Double = 1) throws -> MonochromeBitmap {
        let ean = try EAN13.completed(label.ean)
        guard let price = PriceFormatter.formatted(label.price, currency: label.currency) else { throw LabelError.invalidPrice }
        let geometry = LabelRasterGeometry(layoutHeight: size.heightDots, scale: scale)
        let width = geometry.width
        let height = geometry.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Coordonnées de mise en page (384 points) mises à l'échelle.
            context.cgContext.scaleBy(x: CGFloat(width) / CGFloat(Self.width),
                                      y: CGFloat(height) / CGFloat(size.heightDots))
            drawComposition(label, ean: ean, price: price, size: size, arrangement: arrangement)
        }
        guard let cgImage = image.cgImage else { throw LabelError.rasterFailure }
        // Read through a known RGBA layout; no resizing or interpolation.
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapContext = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LabelError.rasterFailure }
        bitmapContext.interpolationQuality = .none
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var black = [Bool](repeating: false, count: width * height)
        for i in black.indices {
            let p = i * 4
            // Hard threshold keeps the printed output strictly black or white.
            black[i] = (Int(rgba[p]) * 299 + Int(rgba[p + 1]) * 587 + Int(rgba[p + 2]) * 114) < 160_000
        }
        let modules = try EAN13.modules(for: ean)
        let module = geometry.moduleDots
        let left = geometry.barcodeLeft
        let rows = geometry.rows(barcodeRows(size: size, arrangement: arrangement))
        for (index, on) in modules.enumerated() where on {
            for y in rows {
                for dot in 0..<module {
                    black[y * width + left + index * module + dot] = true
                }
            }
        }
        return try RasterEncoder.encodeBlackPixels(black, width: width, height: height)
    }

    /// Image en niveaux de gris (noir ou blanc seulement) pour le SDK Brother.
    /// Aucune interpolation : le SDK reçoit les points tels quels.
    static func grayImage(_ bitmap: MonochromeBitmap) throws -> CGImage {
        let gray = try PackedBitmap.grayscale(bitmap.bytes, width: bitmap.width, height: bitmap.height)
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let image = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: bitmap.width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { throw LabelError.rasterFailure }
        return image
    }

    private static func barcodeRows(size: LabelSize, arrangement: LabelArrangement) -> Range<Int> {
        if arrangement == .current {
            switch size {
            case .compact: return 70..<120
            case .standard: return 84..<154
            case .airy: return 103..<195
            case .large: return 139..<267
            }
        }
        let pair: (Int, Int)
        switch arrangement {
        case .priceFirst: pair = (104, 153)
        case .columns: pair = (111, 160)
        case .barcodeFirst: pair = (48, 105)
        case .centered: pair = (81, 127)
        case .barcodeLast: pair = (137, 183)
        case .current: fatalError("Handled above")
        }
        let factor = Double(size.heightDots) / 208.0
        return Int((Double(pair.0) * factor).rounded())..<Int((Double(pair.1) * factor).rounded())
    }

    private static func drawComposition(_ label: ProductLabel, ean: String, price: String,
                                        size: LabelSize, arrangement: LabelArrangement) {
        if arrangement == .current {
            drawCurrent(label, ean: ean, price: price, size: size)
            return
        }
        let scale = CGFloat(size.heightDots) / 208
        let fontScale = min(1 + CGFloat(size.heightDots - 208) / 600, 1.35)
        func put(_ value: String, _ x: CGFloat, _ top: CGFloat, _ width: CGFloat,
                 _ band: CGFloat, _ font: CGFloat, _ alignment: NSTextAlignment = .left) {
            draw(value, in: CGRect(x: x, y: (top * scale).rounded(), width: width,
                                   height: (band * scale).rounded()),
                 maxSize: (font * fontScale).rounded(), bold: true, alignment: alignment)
        }
        func digits(_ top: CGFloat) {
            put(String(ean.prefix(1)), 18, top, 30, 18, 12, .center)
            put(String(ean.dropFirst().prefix(6)), 55, top, 140, 18, 12, .center)
            put(String(ean.suffix(6)), 205, top, 140, 18, 12, .center)
        }
        let reference = String(format: NSLocalizedString("Réf. %@", comment: "Product reference on label"), label.productReference)
        switch arrangement {
        case .priceFirst:
            put(label.category, 12, 7, 205, 16, 12)
            put(label.shelfReference, 12, 24, 210, 16, 11)
            put(price, 225, 7, 147, 40, 34, .right)
            put(label.priceCaption, 221, 49, 151, 18, 13, .right)
            put(label.name, 12, 69, 360, 29, 26)
            digits(155)
            put(reference, 12, 182, 360, 19, 14, .center)
        case .columns:
            put(label.category, 12, 7, 360, 17, 12)
            put(label.shelfReference, 12, 25, 360, 17, 11)
            put(label.name, 12, 54, 195, 42, 23)
            put(price, 220, 48, 152, 40, 34, .right)
            put(label.priceCaption, 215, 89, 157, 17, 12, .right)
            digits(162)
            put(reference, 12, 187, 360, 18, 14, .center)
        case .barcodeFirst:
            put(label.category, 12, 6, 360, 16, 12)
            put(label.shelfReference, 12, 23, 360, 16, 11)
            digits(107)
            put(label.name, 12, 135, 360, 30, 26)
            put(reference, 12, 167, 205, 17, 13)
            put(label.priceCaption, 12, 187, 205, 17, 13)
            put(price, 225, 173, 147, 33, 31, .right)
        case .centered:
            put(label.category, 12, 6, 360, 17, 12, .center)
            put(label.shelfReference, 12, 25, 360, 16, 11, .center)
            put(label.name, 12, 48, 360, 29, 27, .center)
            digits(129)
            put(reference, 12, 149, 360, 17, 13, .center)
            put(label.priceCaption, 12, 166, 360, 17, 13, .center)
            put(price, 12, 183, 360, 24, 26, .center)
        case .barcodeLast:
            put(label.category, 12, 7, 360, 17, 12)
            put(label.name, 12, 26, 360, 30, 27)
            put(label.shelfReference, 12, 60, 360, 17, 11)
            put(label.priceCaption, 12, 84, 205, 17, 14)
            put(price, 221, 75, 151, 41, 35, .right)
            put(reference, 12, 111, 360, 18, 13, .center)
            digits(186)
        case .current: break
        }
    }

    private static func drawCurrent(_ label: ProductLabel, ean: String, price: String, size: LabelSize) {
        let values: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)
        switch size {
        case .compact: values = (6, 12, 22, 11, 39, 25, 123, 13, 145, 178, 166, 31)
        case .standard: values = (7, 13, 26, 12, 44, 28, 156, 16, 178, 208, 194, 37)
        case .airy: values = (10, 16, 34, 14, 58, 32, 199, 17, 228, 274, 257, 43)
        case .large: values = (14, 18, 43, 16, 75, 38, 274, 18, 310, 369, 346, 47)
        }
        let v = values
        draw(label.category, in: CGRect(x: 12, y: v.0, width: 360, height: 22), maxSize: CGFloat(v.1), bold: true, alignment: .left)
        draw(label.shelfReference, in: CGRect(x: 12, y: v.2, width: 360, height: 22), maxSize: CGFloat(v.3), bold: true, alignment: .left)
        draw(label.name, in: CGRect(x: 12, y: v.4, width: 360, height: 44), maxSize: CGFloat(v.5), bold: true, alignment: .left)
        draw(String(ean.prefix(1)), in: CGRect(x: 22, y: v.6, width: 27, height: 20), maxSize: CGFloat(v.7), bold: true)
        draw(String(ean.dropFirst().prefix(6)), in: CGRect(x: 58, y: v.6, width: 135, height: 20), maxSize: CGFloat(v.7), bold: true)
        draw(String(ean.suffix(6)), in: CGRect(x: 208, y: v.6, width: 135, height: 20), maxSize: CGFloat(v.7), bold: true)
        draw(String(format: NSLocalizedString("Réf. %@", comment: "Product reference on label"), label.productReference), in: CGRect(x: 12, y: v.8, width: 360, height: 25), maxSize: size == .compact ? 12 : size == .standard ? 14 : size == .airy ? 17 : 19, bold: true)
        draw(label.priceCaption, in: CGRect(x: 12, y: v.9, width: 215, height: 27), maxSize: size == .compact ? 15 : size == .standard ? 19 : size == .airy ? 21 : 22, bold: true, alignment: .left)
        draw(price, in: CGRect(x: 223, y: v.10, width: 149, height: 50), maxSize: CGFloat(v.11), bold: true, alignment: .right)
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

    private static func draw(_ text: String, in rect: CGRect, maxSize: CGFloat, bold: Bool, alignment: NSTextAlignment = .center) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
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
        case .invalidPrice: return NSLocalizedString("Prix invalide", comment: "Invalid price error")
        case .rasterFailure: return NSLocalizedString("Impossible de créer le bitmap", comment: "Rasterization error")
        }
    }
}
