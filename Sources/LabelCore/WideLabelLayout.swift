import Foundation

/// Mises en page 80 mm : 576 points de large (72 mm imprimables à 203 dpi).
///
/// Les six dispositions reprennent l'esprit de celles de la 5890, mais
/// profitent de la largeur : le code-barres à gauche laisse une colonne
/// pour le prix à droite. Les coordonnées sont données pour la hauteur
/// Compact (208 points) et suivent la hauteur choisie ; les largeurs restent
/// fixes. Le code-barres garde 3 points par module et 10 modules de marge
/// de chaque côté, comme sur la 5890.
public struct WideLabelLayout: Equatable, Sendable {
    public static let width = 576
    public static let moduleDots = 3
    public static let quietZoneDots = 30
    public static let barcodeWidth = EAN13Width.modules * moduleDots

    public enum Field: String, CaseIterable, Sendable {
        case category, shelfReference, name, reference, priceCaption, price
        case eanFirstDigit, eanLeftDigits, eanRightDigits
    }

    public enum Alignment: Sendable { case left, center, right }

    public struct TextBox: Equatable, Sendable {
        public let field: Field
        public let x: Int, y: Int, width: Int, height: Int
        public let fontSize: Int
        public let alignment: Alignment
    }

    public let height: Int
    public let boxes: [TextBox]
    /// Premier point du premier module.
    public let barcodeLeft: Int
    public let barcodeRows: Range<Int>

    public func box(_ field: Field) -> TextBox? { boxes.first { $0.field == field } }

    /// Hauteur du code-barres et des chiffres, marges comprises.
    public var barcodeBlock: (x: Range<Int>, y: Range<Int>) {
        ((barcodeLeft - Self.quietZoneDots)..<(barcodeLeft + Self.barcodeWidth + Self.quietZoneDots), barcodeRows)
    }

    public static func layout(size: LabelSize, arrangement: LabelArrangement) -> WideLabelLayout {
        let height = size.heightDots
        let scale = Double(height) / 208
        let fontScale = min(1 + Double(height - 208) / 600, 1.35)
        func y(_ value: Int) -> Int { Int((Double(value) * scale).rounded()) }
        func box(_ field: Field, _ x: Int, _ top: Int, _ width: Int, _ band: Int,
                 _ font: Int, _ alignment: Alignment = .left) -> TextBox {
            let start = y(top)
            return TextBox(field: field, x: x, y: start, width: width, height: y(top + band) - start,
                           fontSize: Int((Double(font) * fontScale).rounded()), alignment: alignment)
        }

        // Code à gauche : la marge blanche commence à 12 points du bord.
        let leftCode = 42
        let centeredCode = (width - barcodeWidth) / 2
        var boxes: [TextBox]
        let codeLeft: Int
        let codeRows: (Int, Int)

        switch arrangement {
        case .current:
            codeLeft = leftCode; codeRows = (88, 148)
            boxes = [box(.category, 12, 6, 552, 18, 13),
                     box(.shelfReference, 12, 25, 552, 17, 12),
                     box(.name, 12, 44, 552, 36, 30),
                     box(.reference, 12, 180, 345, 22, 15),
                     box(.priceCaption, 366, 92, 198, 22, 16, .right),
                     box(.price, 366, 118, 198, 56, 46, .right)]
        case .priceFirst:
            codeLeft = leftCode; codeRows = (122, 170)
            boxes = [box(.category, 12, 6, 340, 17, 13),
                     box(.shelfReference, 12, 25, 340, 17, 12),
                     box(.price, 360, 4, 204, 54, 44, .right),
                     box(.priceCaption, 360, 60, 204, 18, 13, .right),
                     box(.name, 12, 84, 552, 32, 28),
                     box(.reference, 366, 150, 198, 22, 15, .right)]
        case .columns:
            codeLeft = leftCode; codeRows = (118, 168)
            boxes = [box(.category, 12, 6, 552, 17, 13),
                     box(.shelfReference, 12, 25, 552, 17, 12),
                     box(.name, 12, 50, 340, 36, 26),
                     box(.price, 360, 46, 204, 46, 40, .right),
                     box(.priceCaption, 360, 94, 204, 18, 13, .right),
                     box(.reference, 366, 176, 198, 22, 14, .right)]
        case .barcodeFirst:
            codeLeft = leftCode; codeRows = (8, 66)
            boxes = [box(.category, 366, 8, 198, 18, 13, .right),
                     box(.shelfReference, 366, 28, 198, 17, 12, .right),
                     box(.reference, 366, 50, 198, 20, 14, .right),
                     box(.name, 12, 98, 552, 34, 28),
                     box(.priceCaption, 12, 150, 280, 20, 15),
                     box(.price, 300, 136, 264, 62, 50, .right)]
        case .centered:
            codeLeft = centeredCode; codeRows = (84, 128)
            boxes = [box(.category, 12, 6, 552, 17, 13, .center),
                     box(.shelfReference, 12, 25, 552, 16, 12, .center),
                     box(.name, 12, 46, 552, 32, 28, .center),
                     box(.reference, 12, 148, 552, 17, 13, .center),
                     box(.priceCaption, 12, 172, 276, 30, 16, .right),
                     box(.price, 296, 166, 268, 40, 36)]
        case .barcodeLast:
            codeLeft = centeredCode; codeRows = (140, 186)
            boxes = [box(.category, 12, 6, 552, 17, 13),
                     box(.name, 12, 26, 552, 32, 28),
                     box(.shelfReference, 12, 62, 340, 17, 12),
                     box(.reference, 12, 92, 320, 20, 14),
                     box(.priceCaption, 366, 62, 198, 18, 13, .right),
                     box(.price, 340, 82, 224, 50, 44, .right)]
        }

        // Chiffres lisibles sous les barres, alignés sur les deux moitiés.
        let digitsTop = codeRows.1 + 2
        boxes += [box(.eanFirstDigit, codeLeft - 26, digitsTop, 22, 18, 13, .center),
                  box(.eanLeftDigits, codeLeft + 9, digitsTop, 126, 18, 13, .center),
                  box(.eanRightDigits, codeLeft + 150, digitsTop, 126, 18, 13, .center)]
        return WideLabelLayout(height: height, boxes: boxes, barcodeLeft: codeLeft,
                               barcodeRows: y(codeRows.0)..<y(codeRows.1))
    }
}

private enum EAN13Width { static let modules = 95 }
