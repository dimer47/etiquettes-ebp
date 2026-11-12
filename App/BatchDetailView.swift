import SwiftUI

/// Écran récap de la multi-impression : reprend le motif de `ArticleDetailView` au PLURIEL.
///  - **Produits** : une carte repliable par produit (ligne compacte / détail complet), avec le
///    réglage « quantité par défaut » du lot en tête.
///  - **Impression** : le modèle d'impression (imprimante, présentation) choisi une fois pour tout
///    le lot, fourni par l'hôte, + le bouton « Imprimer tout » et la progression / pause.
///
/// Toute la mécanique d'impression (services, machine à états) vit dans l'hôte (ContentView) :
/// cette vue n'affiche que l'état et remonte les intentions via des closures.
struct BatchDetailView<PrinterCard: View, PresentationCard: View>: View {
    @ObservedObject var batch: BatchStore

    /// État courant de la file d'impression (nil = pas d'impression en cours).
    let queueState: PrintQueueMachine.State?
    /// Le modèle d'impression (carte imprimante + carte présentation), construit par l'hôte.
    @ViewBuilder let printerCard: () -> PrinterCard
    @ViewBuilder let presentationCard: () -> PresentationCard
    /// Aperçu live d'un produit donné (rendu par l'hôte avec le moteur d'étiquette).
    let preview: (MappedProduct) -> UIImage?
    /// Prêt à imprimer (imprimante connectée, pas déjà en cours).
    let canPrint: Bool

    let onPrintAll: () -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    /// Hook de debug (DEBUG only) : bascule l'échec forcé de la 1re étiquette pour tester la reprise.
    var onToggleDebugFail: (() -> Void)? = nil
    var debugFailArmed = false

    @State private var tab = 0

    var body: some View {
        Group {
            if tab == 0 { productsTab } else { printTab }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("", selection: $tab) {
                Text(NSLocalizedString("Produits", comment: "Products tab (plural)")).tag(0)
                Text(NSLocalizedString("Impression", comment: "Printing tab")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.bar)
        }
        .navigationTitle(String(format: NSLocalizedString("Lot (%d)", comment: "Batch title with count"), batch.count))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Onglet Produits

    private var productsTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                defaultQuantityCard
                if batch.isEmpty {
                    ContentUnavailableView(NSLocalizedString("Lot vide", comment: "Empty batch"),
                                           systemImage: "tray",
                                           description: Text(NSLocalizedString("Ajoutez des produits depuis la liste ou le scan.", comment: "")))
                        .padding(.top, 40)
                } else {
                    ForEach(batch.entries) { entry in
                        productCard(entry)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Réglage « quantité par défaut » du lot, en tête de l'onglet Produits.
    private var defaultQuantityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "number.square.fill").font(.title3).foregroundStyle(.primary)
                Text(NSLocalizedString("Quantité par défaut", comment: "Default quantity")).font(.headline)
                Spacer()
                counter(value: batch.defaultQuantity,
                        onMinus: { if batch.defaultQuantity > 1 { batch.defaultQuantity -= 1 } },
                        onPlus: { if batch.defaultQuantity < 99 { batch.defaultQuantity += 1 } })
            }
            HStack {
                Text(NSLocalizedString("Appliquée à chaque nouveau produit ajouté.", comment: "Default quantity help"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(NSLocalizedString("Appliquer à tout", comment: "Apply default to all")) {
                    batch.applyDefaultToAll()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(batch.isEmpty)
            }
        }
        .padding(16)
        .modifier(BatchCardStyle())
    }

    /// Carte repliable d'un produit : ligne compacte (repliée) ou détail (dépliée).
    private func productCard(_ entry: BatchStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête toujours visible : désignation + prix + chevron de pliage.
            Button { withAnimation(.easeInOut(duration: 0.2)) { batch.toggleExpanded(id: entry.id) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: entry.expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold()).foregroundStyle(.secondary).frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.product.label.name.isEmpty ? "—" : entry.product.label.name)
                            .font(.headline).foregroundStyle(.primary)
                            .lineLimit(expanded(entry) ? nil : 1)
                        if !entry.product.label.price.isEmpty {
                            Text(entry.product.label.price + " " + entry.product.label.currency.symbol)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Ligne compacte d'actions (quantité −/+, retrait), toujours visible.
            HStack {
                counter(value: entry.quantity,
                        onMinus: { batch.decrement(id: entry.id) },
                        onPlus: { batch.increment(id: entry.id) })
                Spacer()
                Button(role: .destructive) { batch.remove(id: entry.id) } label: {
                    Label(NSLocalizedString("Retirer", comment: "Remove from batch"), systemImage: "trash")
                        .labelStyle(.iconOnly).font(.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 10)

            if expanded(entry) {
                Divider().padding(.vertical, 12)
                productDetail(entry.product)
            }
        }
        .padding(16)
        .modifier(BatchCardStyle())
    }

    private func expanded(_ entry: BatchStore.Entry) -> Bool { entry.expanded }

    /// Détail d'un produit (déplié) : aperçu d'étiquette + infos principales, façon onglet Produit.
    private func productDetail(_ product: MappedProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = preview(product) {
                Image(uiImage: image).interpolation(.high).resizable()
                    .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                    .background(.white)
                    .overlay(Rectangle().stroke(Color(.separator), lineWidth: 1))
                    .frame(maxHeight: 130)
                    .accessibilityLabel(NSLocalizedString("Aperçu de l’étiquette", comment: "Label preview"))
            }
            detailRow(NSLocalizedString("Référence", comment: "Reference"), product.label.productReference)
            detailRow(NSLocalizedString("Code-barres", comment: "Barcode"), product.label.ean)
            detailRow(NSLocalizedString("Rayon", comment: "Shelf"), product.label.shelfReference)
            detailRow(NSLocalizedString("Famille", comment: "Family"), product.label.category)
            if let ht = product.priceExclVat {
                detailRow("HT", ht + " " + product.label.currency.symbol)
            }
            if let stock = product.details.realStock {
                detailRow(NSLocalizedString("Stock réel", comment: "Real stock"), stock)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.subheadline).multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Onglet Impression

    private var printTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                printerCard()
                presentationCard()
                summaryCard
                queueStatusCard
                printButton
                #if DEBUG
                if let onToggleDebugFail {
                    Button {
                        onToggleDebugFail()
                    } label: {
                        Label(debugFailArmed
                              ? NSLocalizedString("DEBUG : échec forcé 1re étiquette — ARMÉ", comment: "Debug armed")
                              : NSLocalizedString("DEBUG : forcer un échec à la 1re étiquette", comment: "Debug arm"),
                              systemImage: debugFailArmed ? "exclamationmark.triangle.fill" : "ladybug")
                            .font(.caption)
                    }
                    .foregroundStyle(debugFailArmed ? .orange : .secondary)
                }
                #endif
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var summaryCard: some View {
        HStack {
            Image(systemName: "shippingbox.fill").font(.title3).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Récapitulatif du lot", comment: "Batch summary")).font(.headline)
                Text(String(format: NSLocalizedString("%d produit(s) · %d étiquette(s) au total", comment: "Batch totals"),
                            batch.count, batch.totalLabels))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .modifier(BatchCardStyle())
    }

    /// Carte de progression / pause : visible seulement pendant une impression.
    @ViewBuilder
    private var queueStatusCard: some View {
        switch queueState {
        case .printing(let unit, let total):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProgressView()
                    Text(String(format: NSLocalizedString("Impression %d/%d…", comment: "Printing N of M"), unit + 1, total))
                        .font(.headline)
                }
                ProgressView(value: Double(unit), total: Double(total))
            }
            .padding(16)
            .modifier(BatchCardStyle())

        case .paused(let unit, let total, let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(String(format: NSLocalizedString("En pause sur l’étiquette %d/%d", comment: "Paused at N of M"), unit + 1, total),
                      systemImage: "pause.circle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Text(NSLocalizedString("Corrigez le problème (rouleau, imprimante), puis reprenez.", comment: "Pause help"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { onRetry() } label: {
                        Label(NSLocalizedString("Relancer", comment: "Retry label"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { onSkip() } label: {
                        Label(NSLocalizedString("Ignorer", comment: "Skip label"), systemImage: "forward.end")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { onCancel() } label: {
                    Text(NSLocalizedString("Annuler le reste", comment: "Cancel remaining")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .modifier(BatchCardStyle())

        case .done(let printed, let skipped):
            HStack {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                Text(skipped == 0
                     ? String(format: NSLocalizedString("%d étiquette(s) imprimée(s)", comment: "Printed count"), printed)
                     : String(format: NSLocalizedString("%d imprimée(s), %d ignorée(s)", comment: "Printed and skipped"), printed, skipped))
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            .modifier(BatchCardStyle())

        case .idle, .none:
            EmptyView()
        }
    }

    private var isPrinting: Bool {
        if case .printing = queueState { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = queueState { return true }
        return false
    }

    private var printButton: some View {
        Button { onPrintAll() } label: {
            Label(isPrinting
                  ? NSLocalizedString("Impression en cours…", comment: "Printing in progress")
                  : String(format: NSLocalizedString("Imprimer tout (%d)", comment: "Print all N labels"), batch.totalLabels),
                  systemImage: "printer.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(batch.isEmpty || isPrinting || isPaused || !canPrint)
    }

    // MARK: - Compteur −/+ réutilisable (même ergonomie que la carte quantité mono-produit)

    private func counter(value: Int, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onMinus) {
                Image(systemName: "minus").frame(width: 44, height: 34).contentShape(Rectangle())
            }
            .disabled(value <= 1)
            Text("\(value)").font(.headline.monospacedDigit()).frame(minWidth: 40)
            Button(action: onPlus) {
                Image(systemName: "plus").frame(width: 44, height: 34).contentShape(Rectangle())
            }
            .disabled(value >= 99)
        }
        .buttonStyle(.bordered)
    }
}

private struct BatchCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                       in: RoundedRectangle(cornerRadius: 14))
    }
}
