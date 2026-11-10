import SwiftUI

/// Fiche d'un article EBP, en deux onglets au niveau de l'article :
///  - **Produit** : les infos récupérées (lecture seule), TTC en gros + HT en petit (écran only).
///  - **Impression** : l'écran d'impression soigné (carte imprimante, présentation graphique,
///    aperçu live, quantité, bouton Imprimer) — fourni par `ContentView`, qui possède tout le
///    moteur d'impression et les feuilles associées.
struct ArticleDetailView<Impression: View>: View {
    let product: MappedProduct
    /// Contenu de l'onglet Impression, construit par l'hôte (ContentView).
    @ViewBuilder let impression: () -> Impression

    @State private var tab = 0

    private var label: ProductLabel { product.label }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(NSLocalizedString("Produit", comment: "Product tab")).tag(0)
                Text(NSLocalizedString("Impression", comment: "Printing tab")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 { productTab } else { impression() }
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
}
