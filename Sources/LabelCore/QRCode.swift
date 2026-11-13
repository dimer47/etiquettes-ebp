import Foundation
import CoreImage

/// Génération d'un QR code natif (CoreImage `CIQRCodeGenerator`) sous forme de GRILLE DE MODULES
/// carrés (noir = true). Indépendant de UIKit : le moteur d'impression peint ensuite ces modules
/// en points, mis à l'échelle pour tenir dans la cellule — exactement comme le code-barres EAN.
///
/// Le QR est monochrome par nature (modules noirs sur fond blanc) : compatible tel quel avec le
/// seuillage noir/blanc du moteur thermique.
public enum QRCode {
    /// Grille carrée de modules pour `string`. `[]` si la chaîne est vide ou si la génération
    /// échoue. Chaque sous-tableau est une rangée ; `grid[y][x] == true` = module noir.
    ///
    /// Niveau de correction d'erreur « M » (équilibre densité/robustesse) : adapté à une petite
    /// étiquette où l'on veut limiter le nombre de modules pour garder des modules lisibles.
    public static func modules(for string: String, correction: String = "M") -> [[Bool]] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return [] }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correction, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return [] }

        // CoreImage rend 1 module = 1 pixel (+ zone de garde incluse). On lit ces pixels via un
        // contexte bitmap : chaque pixel devient un module.
        let extent = output.extent
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0 else { return [] }

        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(output, from: extent) else { return [] }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmap = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        bitmap.interpolationQuality = .none
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CoreImage pose l'origine en bas à gauche ; on inverse les rangées pour obtenir un
        // repère écran (origine en haut à gauche), comme le reste du moteur de rendu.
        var grid = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let p = (y * width + x) * 4
                // Sombre = module noir (QR CoreImage : modules noirs, fond blanc).
                let luma = Int(pixels[p]) * 299 + Int(pixels[p + 1]) * 587 + Int(pixels[p + 2]) * 114
                grid[height - 1 - y][x] = luma < 160_000
            }
        }
        return grid
    }
}
