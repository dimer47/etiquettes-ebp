import SwiftUI

/// Fiche d'un article EBP, en deux onglets au niveau de l'article :
///  - **Produit** : les infos récupérées (lecture seule), TTC en gros + HT en petit (écran only).
///  - **Impression** : quantité, format, bouton imprimer.
struct ArticleDetailView: View {
    let product: MappedProduct
    /// Liaisons vers le format courant de l'app (mêmes @AppStorage que l'écran d'impression).
    @Binding var sizeRaw: String
    @Binding var arrangementRaw: String
    /// Appelé sur « Imprimer » : (étiquette, quantité).
    let onPrint: (ProductLabel, Int) -> Void

    @State private var tab = 0
    @State private var quantity = 1

    private var label: ProductLabel { product.label }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(NSLocalizedString("Produit", comment: "Product tab")).tag(0)
                Text(NSLocalizedString("Impression", comment: "Printing tab")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 { productTab } else { printTab }
        }
        .navigationTitle(label.name.isEmpty ? NSLocalizedString("Article", comment: "Article") : label.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Onglet Produit (lecture seule)

    private var productTab: some View {
        Form {
            Section(NSLocalizedString("Produit", comment: "Product")) {
                LabeledContent(NSLocalizedString("Libellé", comment: "Name"),
                               value: label.name.isEmpty ? "—" : label.name)
                if !label.productReference.isEmpty {
                    LabeledContent(NSLocalizedString("Référence", comment: "Reference"), value: label.productReference)
                }
                if !label.shelfReference.isEmpty {
                    LabeledContent(NSLocalizedString("Rayon", comment: "Shelf"), value: label.shelfReference)
                }
                if !label.category.isEmpty {
                    LabeledContent(NSLocalizedString("Famille", comment: "Family"), value: label.category)
                }
                eanRow
            }

            Section(NSLocalizedString("Prix", comment: "Price")) {
                LabeledContent {
                    Text(label.price.isEmpty ? "—" : "\(label.price) \(label.currency.symbol)")
                        .font(.title3.weight(.semibold))
                } label: { Text("TTC") }
                if let ht = product.priceExclVat {
                    LabeledContent {
                        Text("\(ht) \(label.currency.symbol)").foregroundStyle(.secondary)
                    } label: { Text("HT") }
                    .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private var eanRow: some View {
        if !label.ean.isEmpty {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(label.ean).font(.body.monospaced())
                    if product.eanWasInvalid {
                        Label(NSLocalizedString("Code-barres non valide", comment: "Invalid barcode"),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            } label: { Text(NSLocalizedString("Code-barres", comment: "Barcode")) }
        }
    }

    // MARK: - Onglet Impression

    private var printTab: some View {
        Form {
            Section(NSLocalizedString("Impression", comment: "Printing")) {
                Stepper(value: $quantity, in: 1...99) {
                    LabeledContent(NSLocalizedString("Quantité", comment: "Quantity"), value: "\(quantity)")
                }
                Picker(NSLocalizedString("Hauteur", comment: "Height"), selection: $sizeRaw) {
                    ForEach(LabelSize.allCases) { size in Text(size.title).tag(size.rawValue) }
                }
                Picker(NSLocalizedString("Disposition", comment: "Arrangement"), selection: $arrangementRaw) {
                    ForEach(LabelArrangement.allCases) { a in Text(a.title).tag(a.rawValue) }
                }
            }

            Section {
                Button {
                    onPrint(label, quantity)
                } label: {
                    Label(String(format: NSLocalizedString("Imprimer %d étiquette(s)", comment: "Print N labels"), quantity),
                          systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
