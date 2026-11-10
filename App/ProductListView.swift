import SwiftUI

/// Modèle de recherche d'articles EBP via la gateway : pagination, scroll infini,
/// anti-rebond de la saisie. Les types LabelCore (GatewayClient, EBPItem…) sont in-module.
@MainActor
final class EBPSearchModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, loadingMore, error(String) }

    @Published var query = ""
    @Published private(set) var items: [EBPItem] = []
    @Published private(set) var phase: Phase = .idle

    private let config: GatewayConfig
    private let client: GatewayClient
    private let pageSize = 50
    private var offset = 0
    private var total = 0
    private var searchTask: Task<Void, Never>?

    init(config: GatewayConfig) {
        self.config = config
        self.client = GatewayClient(config: config)
    }

    /// Reste-t-il des articles à charger ?
    private var canLoadMore: Bool { items.count < total }

    /// Recharge depuis le début pour la recherche courante (avec anti-rebond).
    func search(debounced: Bool = true) {
        searchTask?.cancel()
        let term = query
        searchTask = Task { [weak self] in
            if debounced { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await self?.reload(term: term)
        }
    }

    func reloadNow() { search(debounced: false) }

    private func reload(term: String) async {
        phase = .loading
        offset = 0
        do {
            let page = try await client.items(ItemsQuery(offset: 0, limit: pageSize, search: term.isEmpty ? nil : term))
            guard !Task.isCancelled else { return }
            items = page.items
            total = page.paging?.total ?? page.items.count
            offset = page.items.count
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .error(Self.message(for: error))
        }
    }

    /// Charge la page suivante (déclenché quand la dernière ligne apparaît).
    func loadMoreIfNeeded(current item: EBPItem) {
        guard phase == .loaded, canLoadMore,
              item == items.last else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard phase == .loaded, canLoadMore else { return }
        phase = .loadingMore
        let term = query
        do {
            let page = try await client.items(ItemsQuery(offset: offset, limit: pageSize, search: term.isEmpty ? nil : term))
            items.append(contentsOf: page.items)
            total = page.paging?.total ?? total
            offset += page.items.count
            phase = .loaded
        } catch {
            phase = .error(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        guard let e = error as? GatewayError else { return error.localizedDescription }
        switch e {
        case .unauthorized: return NSLocalizedString("Jeton refusé : vérifiez la configuration dans Réglages.", comment: "")
        case .forbidden(let m): return m.isEmpty ? NSLocalizedString("Compte EBP indisponible.", comment: "") : m
        case .folderRequired: return NSLocalizedString("Aucun dossier ciblé par le jeton.", comment: "")
        case .jobTimedOut: return NSLocalizedString("La gateway met trop de temps à répondre. Réessayez.", comment: "")
        case .jobFailed(let errs): return errs.first ?? NSLocalizedString("La requête a échoué côté EBP.", comment: "")
        case .transport(let m): return String(format: NSLocalizedString("Gateway injoignable : %@", comment: ""), m)
        case .invalidConfig: return NSLocalizedString("Configuration invalide (URL ou jeton).", comment: "")
        case .decoding(let m): return String(format: NSLocalizedString("Réponse illisible : %@", comment: ""), m)
        case .http(let code): return String(format: NSLocalizedString("Erreur HTTP %d.", comment: ""), code)
        case .badRequest(let m): return m.isEmpty ? NSLocalizedString("Requête refusée.", comment: "") : m
        }
    }
}

/// Écran RACINE (app appairée) : liste et recherche des articles EBP. Sélectionner un article
/// pousse sa fiche à onglets Produit / Impression. L'onglet Impression (écran d'impression soigné)
/// est fourni par l'hôte via `impression` ; `onSelect` prévient l'hôte pour alimenter l'étiquette.
struct ProductListView<Impression: View, Sheets: View>: View {
    let config: GatewayConfig
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onSelect: (MappedProduct) -> Void
    @ViewBuilder let impression: (MappedProduct) -> Impression
    @ViewBuilder let sheets: () -> Sheets

    @StateObject private var model: EBPSearchModel
    @State private var selected: MappedProduct?

    init(config: GatewayConfig,
         onOpenSettings: @escaping () -> Void,
         onOpenHistory: @escaping () -> Void,
         onSelect: @escaping (MappedProduct) -> Void,
         @ViewBuilder impression: @escaping (MappedProduct) -> Impression,
         @ViewBuilder sheets: @escaping () -> Sheets) {
        self.config = config
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onSelect = onSelect
        self.impression = impression
        self.sheets = sheets
        _model = StateObject(wrappedValue: EBPSearchModel(config: config))
    }

    var body: some View {
        content
            .navigationTitle(NSLocalizedString("Articles EBP", comment: "EBP items"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onOpenHistory() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel(NSLocalizedString("Historique", comment: "History"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onOpenSettings() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(NSLocalizedString("Réglages", comment: "Settings"))
                }
            }
            .searchable(text: $model.query,
                        prompt: NSLocalizedString("Rechercher (libellé ou référence)", comment: "Search"))
            .onChange(of: model.query) { _, _ in model.search() }
            .onAppear { if model.items.isEmpty { model.reloadNow() } }
            .navigationDestination(item: $selected) { product in
                ArticleDetailView(product: product, impression: { impression(product) }, sheets: sheets)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading where model.items.isEmpty:
            ProgressView(NSLocalizedString("Chargement…", comment: "Loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message) where model.items.isEmpty:
            ContentUnavailableView {
                Label(NSLocalizedString("Impossible de charger", comment: "Cannot load"), systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                Button(NSLocalizedString("Réessayer", comment: "Retry")) { model.reloadNow() }.buttonStyle(.borderedProminent)
            }
        default:
            list
        }
    }

    private var list: some View {
        List {
            if model.items.isEmpty {
                ContentUnavailableView(NSLocalizedString("Aucun article", comment: "No item"),
                                       systemImage: "magnifyingglass",
                                       description: Text(NSLocalizedString("Aucun résultat pour cette recherche.", comment: "")))
            }
            ForEach(model.items, id: \.self) { item in
                Button { select(item) } label: { row(item) }
                    .onAppear { model.loadMoreIfNeeded(current: item) }
            }
            if model.phase == .loadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ item: EBPItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.caption ?? item.desComClear ?? "—")
                .font(.headline).foregroundStyle(.primary)
            HStack(spacing: 10) {
                if let id = item.id?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
                    Text(id).font(.caption).foregroundStyle(.secondary)
                }
                if let barcode = item.barCode, !barcode.isEmpty {
                    Text(barcode).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let ttc = item.salePriceVatIncluded {
                    Text(priceText(ttc)).font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func priceText(_ value: Decimal) -> String {
        var v = value, r = Decimal()
        NSDecimalRound(&r, &v, 2, .plain)
        let f = NumberFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return (f.string(from: r as NSDecimalNumber) ?? "\(r)") + " €"
    }

    private func select(_ item: EBPItem) {
        let product = EBPProductMapper.map(item)
        onSelect(product)        // alimente l'étiquette courante AVANT de pousser la fiche (aperçu live)
        selected = product
    }
}
