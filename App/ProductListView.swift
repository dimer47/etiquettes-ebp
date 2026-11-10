import SwiftUI

/// Modèle de recherche d'articles EBP via la gateway : pagination, scroll infini,
/// anti-rebond de la saisie. Les types LabelCore (GatewayClient, EBPItem…) sont in-module.
@MainActor
final class EBPSearchModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, loadingMore, error(String) }

    /// Critères de tri proposés à l'utilisateur.
    enum SortField: String, CaseIterable, Identifiable {
        case reference, caption, price
        var id: String { rawValue }
        /// Champ EBP correspondant (OrderByValue).
        var ebpField: String {
            switch self {
            case .reference: return "Id"
            case .caption: return "Caption"
            case .price: return "SalePriceVatIncluded"
            }
        }
        var title: String {
            switch self {
            case .reference: return NSLocalizedString("Référence", comment: "Sort by reference")
            case .caption: return NSLocalizedString("Libellé", comment: "Sort by caption")
            case .price: return NSLocalizedString("Prix", comment: "Sort by price")
            }
        }
    }

    @Published var query = ""
    @Published var familyFilter = ""        // id de famille (ex. FAR00004), vide = toutes
    @Published var subFamilyFilter = ""     // id de sous-famille, vide = toutes
    @Published var priceMinText = ""        // prix TTC min (texte, vide = aucun)
    @Published var priceMaxText = ""        // prix TTC max
    @Published var onlyActive = false       // n'afficher que les articles actifs
    @Published var onlyInStock = false      // n'afficher que les articles en stock
    @Published var sortField: SortField = .reference
    @Published var sortDescending = false
    @Published private(set) var items: [EBPItem] = []
    @Published private(set) var phase: Phase = .idle

    /// Un filtre (hors recherche texte et tri) est-il actif ?
    var hasActiveFilters: Bool {
        !familyFilter.trimmingCharacters(in: .whitespaces).isEmpty
            || !subFamilyFilter.trimmingCharacters(in: .whitespaces).isEmpty
            || !priceMinText.trimmingCharacters(in: .whitespaces).isEmpty
            || !priceMaxText.trimmingCharacters(in: .whitespaces).isEmpty
            || onlyActive || onlyInStock
    }

    /// Remet les filtres à zéro. Ne recharge pas : l'appelant déclenche le rechargement
    /// (après fermeture de la feuille) via `reloadNow()`.
    /// Remet les filtres à zéro. Ne recharge pas : l'appelant déclenche le rechargement
    /// (après fermeture de la feuille) via `reloadNow()`.
    func clearFilters() {
        familyFilter = ""; subFamilyFilter = ""; priceMinText = ""; priceMaxText = ""
        onlyActive = false; onlyInStock = false
        sortField = .reference; sortDescending = false
    }

    /// Empreinte des filtres et du tri courants : permet de ne recharger que s'ils ont
    /// réellement changé après la fermeture de la feuille.
    var filtersSignature: String {
        [familyFilter.trimmingCharacters(in: .whitespaces),
         subFamilyFilter.trimmingCharacters(in: .whitespaces),
         priceMinText.trimmingCharacters(in: .whitespaces),
         priceMaxText.trimmingCharacters(in: .whitespaces),
         onlyActive ? "1" : "0", onlyInStock ? "1" : "0",
         sortField.rawValue, sortDescending ? "d" : "a"].joined(separator: "|")
    }

    private func currentQuery(offset: Int) -> ItemsQuery {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = familyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let subFamily = subFamilyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return ItemsQuery(offset: offset, limit: pageSize,
                          orderBy: sortField.ebpField, orderDescending: sortDescending,
                          search: term.isEmpty ? nil : term,
                          familyId: family.isEmpty ? nil : family,
                          subFamilyId: subFamily.isEmpty ? nil : subFamily,
                          priceMin: Self.decimal(priceMinText),
                          priceMax: Self.decimal(priceMaxText),
                          activeOnly: onlyActive, inStockOnly: onlyInStock)
    }

    private static func decimal(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private let config: GatewayConfig
    private let client: GatewayClient
    private let pageSize = 50
    private var offset = 0
    private var total = 0
    /// La dernière page reçue était-elle pleine ? (critère fiable de « il reste des pages »,
    /// même si EBP ne renvoie pas un `total` exploitable sur de très gros catalogues).
    private var lastPageWasFull = true
    private var searchTask: Task<Void, Never>?
    /// Incrémenté à chaque rechargement complet. Un `loadMore` d'une génération périmée
    /// (filtre changé entre-temps) est ignoré, pour ne pas mélanger deux jeux de résultats.
    private var generation = 0
    /// Clés de ligne déjà présentes, pour dédoublonner les pages qui se chevauchent.
    private var seenRowIDs: Set<String> = []

    init(config: GatewayConfig, session: HTTPSession = URLSession.shared) {
        self.config = config
        self.client = GatewayClient(config: config, session: session)
    }

    /// Reste-t-il des articles à charger ? On continue tant que la dernière page était pleine
    /// (pagination « au fur et à mesure »). Si `total` est connu et fiable, on respecte aussi sa borne.
    private var canLoadMore: Bool {
        guard lastPageWasFull else { return false }
        if total > 0 { return items.count < total }
        return true   // total inconnu/0 : on se fie au remplissage de page
    }

    /// Recharge depuis le début pour la recherche/filtres courants (avec anti-rebond).
    func search(debounced: Bool = true) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if debounced { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reloadNow() { search(debounced: false) }

    /// Rechargement attendu (pour `.refreshable` : pull-to-refresh).
    func refresh() async {
        searchTask?.cancel()
        await reload()
    }

    private func reload() async {
        generation &+= 1
        let gen = generation
        phase = .loading
        offset = 0
        do {
            let page = try await client.items(currentQuery(offset: 0))
            guard !Task.isCancelled, gen == generation else { return }
            // Dédoublonnage par identité de ligne (pages qui se chevauchent).
            var seen = Set<String>()
            let deduped = page.items.filter { seen.insert($0.rowID).inserted }
            items = deduped
            seenRowIDs = seen
            total = page.paging?.total ?? 0
            offset = page.items.count
            lastPageWasFull = page.items.count >= pageSize
            phase = .loaded
        } catch {
            guard !Task.isCancelled, gen == generation else { return }
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
        let gen = generation
        phase = .loadingMore
        do {
            let page = try await client.items(currentQuery(offset: offset))
            // Un rechargement complet (filtre changé) a eu lieu entre-temps : page périmée, on ignore.
            guard gen == generation else { return }
            // N'ajoute que les lignes pas encore présentes (pages qui se chevauchent).
            let fresh = page.items.filter { seenRowIDs.insert($0.rowID).inserted }
            items.append(contentsOf: fresh)
            if let t = page.paging?.total, t > 0 { total = t }
            offset += page.items.count
            lastPageWasFull = page.items.count >= pageSize
            phase = .loaded
        } catch {
            guard gen == generation else { return }
            phase = .error(Self.message(for: error))
        }
    }

    /// Recherche un article par code-barres scanné (interroge EBP, même hors liste chargée).
    /// Renvoie le produit mappé, ou nil si aucun article ne porte ce code.
    func lookupBarcode(_ code: String) async throws -> MappedProduct? {
        guard let item = try await client.itemByBarcode(code) else { return nil }
        return EBPProductMapper.map(item)
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
    @State private var showingFilters = false
    /// Action de rechargement à exécuter une fois la feuille de filtres refermée
    /// (recharger ne marche pas de façon fiable depuis la feuille qui se démonte).
    @State private var pendingReload: PendingReload?
    @State private var showingScanner = false

    private enum PendingReload { case apply, reset }
    @State private var scanLookupInProgress = false
    @State private var scanMessage: String?
    /// Focus des champs de la feuille filtres : on le coupe avant d'appliquer pour forcer les
    /// TextField (clavier décimal, sans touche Entrée) à committer leur valeur au binding.
    @FocusState private var filterFieldFocused: Bool
    /// Empreinte des filtres à l'ouverture de la feuille : on ne recharge à la fermeture que
    /// si elle a changé (évite une requête inutile quand on ferme sans rien modifier).
    @State private var filtersSignatureAtOpen = ""

    init(config: GatewayConfig,
         session: HTTPSession = URLSession.shared,
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
        _model = StateObject(wrappedValue: EBPSearchModel(config: config, session: session))
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
                    Button { scanMessage = nil; showingScanner = true } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel(NSLocalizedString("Scanner un code-barres", comment: "Scan barcode"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        Image(systemName: model.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill"
                                                                  : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(NSLocalizedString("Filtres", comment: "Filters"))
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
            .onChange(of: showingFilters) { wasShown, isShown in
                if isShown {
                    // À l'ouverture : mémorise l'état des filtres pour le comparer à la fermeture.
                    filtersSignatureAtOpen = model.filtersSignature
                    return
                }
                guard wasShown else { return }
                let reset = (pendingReload == .reset)
                pendingReload = nil
                // Décalé d'un cycle : laisse les TextField (clavier décimal) committer leur
                // valeur au binding avant de lire l'empreinte et la requête.
                Task { @MainActor in
                    if reset { model.clearFilters() }
                    // Ne recharge que si les filtres ont réellement changé (ou après un reset).
                    if reset || model.filtersSignature != filtersSignatureAtOpen {
                        model.reloadNow()
                    }
                }
            }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .sheet(isPresented: $showingScanner) { scannerSheet }
            .overlay { if scanLookupInProgress { scanLookupOverlay } }
            .alert(NSLocalizedString("Article introuvable", comment: "Not found"),
                   isPresented: Binding(get: { scanMessage != nil }, set: { if !$0 { scanMessage = nil } })) {
                Button("OK") { scanMessage = nil }
            } message: { Text(scanMessage ?? "") }
            .navigationDestination(item: $selected) { product in
                ArticleDetailView(product: product, impression: { impression(product) }, sheets: sheets)
            }
    }

    /// Scanner de code-barres / QR : au scan, on interroge EBP par code-barres.
    private var scannerSheet: some View {
        NavigationStack {
            ZStack {
                QRScannerView(
                    onFound: { code in handleScannedCode(code) },
                    onError: { message in showingScanner = false; scanMessage = message },
                    types: QRScannerView.productCodeTypes
                )
                .ignoresSafeArea(edges: .bottom)

                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 260, height: 180)
                    .allowsHitTesting(false)
            }
            .navigationTitle(NSLocalizedString("Scanner un article", comment: "Scan article"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Annuler", comment: "Cancel")) { showingScanner = false }
                }
            }
        }
    }

    private var scanLookupOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ProgressView(NSLocalizedString("Recherche de l’article…", comment: "Looking up"))
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Code scanné → recherche EBP par code-barres → ouvre la fiche, ou signale l'absence.
    private func handleScannedCode(_ code: String) {
        showingScanner = false
        scanLookupInProgress = true
        Task { @MainActor in
            do {
                if let product = try await model.lookupBarcode(code) {
                    onSelect(product)
                    selected = product
                } else {
                    scanMessage = String(format: NSLocalizedString("Aucun article avec le code-barres %@.", comment: "No item for barcode"), code)
                }
            } catch {
                scanMessage = EBPSearchModel.message(for: error)
            }
            scanLookupInProgress = false
        }
    }

    /// Feuille de filtrage et de tri de la liste.
    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("Disponibilité", comment: "Availability")) {
                    Toggle(NSLocalizedString("En stock uniquement", comment: "In stock only"), isOn: $model.onlyInStock)
                    Toggle(NSLocalizedString("Articles actifs uniquement", comment: "Active only"), isOn: $model.onlyActive)
                }
                Section(NSLocalizedString("Famille", comment: "Family")) {
                    TextField(NSLocalizedString("Code famille (ex. FAR00004)", comment: "Family code"),
                              text: $model.familyFilter)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($filterFieldFocused)
                    TextField(NSLocalizedString("Code sous-famille (optionnel)", comment: "Sub-family code"),
                              text: $model.subFamilyFilter)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($filterFieldFocused)
                }
                Section(NSLocalizedString("Prix de vente TTC", comment: "Price filter")) {
                    HStack {
                        Text(NSLocalizedString("Min", comment: "Min"))
                        TextField("0", text: $model.priceMinText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($filterFieldFocused)
                        Text("€").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(NSLocalizedString("Max", comment: "Max"))
                        TextField("—", text: $model.priceMaxText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($filterFieldFocused)
                        Text("€").foregroundStyle(.secondary)
                    }
                }
                Section(NSLocalizedString("Tri", comment: "Sort")) {
                    Picker(NSLocalizedString("Trier par", comment: "Sort by"), selection: $model.sortField) {
                        ForEach(EBPSearchModel.SortField.allCases) { field in
                            Text(field.title).tag(field)
                        }
                    }
                    Toggle(NSLocalizedString("Ordre décroissant", comment: "Descending"), isOn: $model.sortDescending)
                }
                Section {
                    Button(NSLocalizedString("Appliquer", comment: "Apply")) {
                        filterFieldFocused = false   // force le commit des champs (clavier décimal)
                        showingFilters = false
                        pendingReload = .apply
                    }
                    if model.hasActiveFilters {
                        Button(NSLocalizedString("Réinitialiser les filtres", comment: "Reset filters"), role: .destructive) {
                            filterFieldFocused = false
                            showingFilters = false
                            pendingReload = .reset
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Filtres et tri", comment: "Filters and sort"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(NSLocalizedString("Fermer", comment: "Close")) { showingFilters = false } }
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
            ForEach(model.items, id: \.rowID) { item in
                Button { select(item) } label: { row(item) }
                    .onAppear { model.loadMoreIfNeeded(current: item) }
            }
            if model.phase == .loadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
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
