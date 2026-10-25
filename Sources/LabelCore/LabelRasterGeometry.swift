import Foundation

/// Dimensions d'une étiquette dessinée à une autre résolution que la 5890.
///
/// La mise en page est conçue sur la tête de la 5890 : 384 points de large,
/// 8 points par millimètre, modules EAN de 3 points. Pour une Brother, la même
/// mise en page est dessinée à `scale` fois cette taille, pour arriver à peu
/// près à la résolution de la tête (`BRLMPrinterModelSpec.xdpi`) à la taille
/// où le SDK posera l'image sur le papier.
///
/// Le code-barres garde des modules d'un nombre entier de pixels : il n'est
/// jamais lissé, seulement épaissi par pas entiers. À `scale == 1`, toutes les
/// valeurs sont celles de l'impression 5890.
public struct LabelRasterGeometry: Equatable, Sendable {
    public static let layoutWidth = 384
    public static let layoutDotsPerMM = 8.0
    public static let baseModuleDots = 3
    public static let quietZoneModules = 10
    public static let eanModules = 95

    public let scale: Double
    /// Largeur en pixels, multiple de 8 (format 1 bit par point).
    public let width: Int
    public let height: Int
    /// Largeur d'un module EAN, en pixels entiers.
    public let moduleDots: Int

    public init(layoutHeight: Int, scale: Double) {
        let scale = min(8, max(0.5, scale.isFinite ? scale : 1))
        self.scale = scale
        width = max(8, Int((Double(Self.layoutWidth) * scale / 8).rounded()) * 8)
        height = max(1, Int((Double(layoutHeight) * scale).rounded()))
        let modulesWithQuietZones = Self.eanModules + 2 * Self.quietZoneModules
        let fitting = max(1, width / modulesWithQuietZones)
        moduleDots = max(1, min(Int((Double(Self.baseModuleDots) * scale).rounded()), fitting))
    }

    public var quietZoneDots: Int { Self.quietZoneModules * moduleDots }
    public var barcodeWidth: Int { Self.eanModules * moduleDots }

    /// Premier pixel du premier module, code centré dans la largeur.
    public var barcodeLeft: Int {
        (width - (barcodeWidth + 2 * quietZoneDots)) / 2 + quietZoneDots
    }

    /// Lignes de la mise en page converties en lignes de pixels.
    public func rows(_ layoutRows: Range<Int>) -> Range<Int> {
        let lower = min(height, Int((Double(layoutRows.lowerBound) * scale).rounded()))
        let upper = min(height, max(lower, Int((Double(layoutRows.upperBound) * scale).rounded())))
        return lower..<upper
    }

    /// Taille de l'étiquette, en millimètres, sur la 5890.
    public static func layoutSizeMM(layoutHeight: Int) -> (width: Double, height: Double) {
        (Double(layoutWidth) / layoutDotsPerMM, Double(layoutHeight) / layoutDotsPerMM)
    }

    /// Taille imprimée une fois l'image mise à l'échelle de la page en gardant
    /// ses proportions (`fitPageAspect`). `area.length` nil : support continu.
    public static func fittedSizeMM(layoutHeight: Int,
                                    area: (width: Double, length: Double?)) -> (width: Double, height: Double) {
        let label = layoutSizeMM(layoutHeight: layoutHeight)
        var factor = area.width / label.width
        if let length = area.length { factor = min(factor, length / label.height) }
        factor = max(0, factor)
        return (label.width * factor, label.height * factor)
    }

    /// Échelle de rendu pour qu'une image posée sur `area` arrive à `dpi`.
    public static func scale(layoutHeight: Int, area: (width: Double, length: Double?), dpi: Double) -> Double {
        let dpi = dpi > 0 ? dpi : 203
        let fitted = fittedSizeMM(layoutHeight: layoutHeight, area: area)
        let pixels = fitted.width / 25.4 * dpi
        return min(8, max(0.5, pixels / Double(layoutWidth)))
    }
}

/// Conversion d'un bitmap 1 bit (bit 7 = pixel de gauche, lignes alignées
/// sur l'octet) en niveaux de gris 8 bits : 0 pour noir, 255 pour blanc.
/// C'est le format remis au SDK Brother sous forme de `CGImage`.
public enum PackedBitmap {
    public enum ConversionError: Error, Equatable { case invalidDimensions }

    public static func grayscale(_ bytes: [UInt8], width: Int, height: Int) throws -> [UInt8] {
        let widthBytes = (width + 7) / 8
        guard width > 0, height > 0, bytes.count == widthBytes * height else {
            throw ConversionError.invalidDimensions
        }
        var gray = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width where bytes[y * widthBytes + x / 8] & UInt8(0x80 >> (x % 8)) != 0 {
                gray[y * width + x] = 0
            }
        }
        return gray
    }
}
