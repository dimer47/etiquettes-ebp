import SwiftUI
import PocketPrinter5890Kit

struct ContentView: View {
    @ObservedObject var gateway: GatewaySettings
    @StateObject private var printer = PrinterManager()
    @StateObject private var setup = PrinterSetup()
    @StateObject private var brother = BrotherPrinterService()
    @StateObject private var netum = NetumPrinterService()
    @StateObject private var thumbnailStore = LabelThumbnailStore()
    @StateObject private var history = LabelHistoryStore()
    /// Étiquette courante : alimentée par l'article EBP sélectionné (plus de saisie manuelle).
    @State private var label = ProductLabel()
    @State private var showingPrinters = false
    @State private var showingSettings = false
    @State private var showingPresentation = false
    @State private var showingHistory = false
    @State private var message: String?
    @State private var ebpQuantity = 1
    @AppStorage("labelSize") private var selectedSize = LabelSize.standard.rawValue
    @AppStorage("labelArrangement") private var selectedArrangement = LabelArrangement.current.rawValue

    private var labelSize: LabelSize { LabelSize(rawValue: selectedSize) ?? .standard }
    private var labelArrangement: LabelArrangement { LabelArrangement(rawValue: selectedArrangement) ?? .current }

    private var isBrother: Bool { setup.brand == .brother }
    private var isNetum: Bool { setup.brand == .netum }
    /// 576 points pour les dispositions 80 mm de la NETUM, 384 sinon.
    private var layoutWidth: Int { isNetum ? setup.netum.paper.layoutWidth : LabelRenderer.width }
    private var layoutWidthMM: Int { layoutWidth / 8 }
    /// Prête à recevoir un travail : 5890 connectée, ou Brother choisie avec
    /// une connexion que le modèle accepte.
    private var printerReady: Bool {
        if isNetum { return netum.connected }
        if isBrother {
            guard brother.canPrint, let target = brother.target else { return false }
            return setup.brotherModel.appConnections.contains(target.connection)
        }
        return printer.connected
    }
    private var isPrinting: Bool { isNetum ? netum.isBusy : isBrother ? brother.isBusy : printer.printing }
    private var printedSizeText: String {
        guard isBrother else { return "\(layoutWidthMM) × \(labelSize.heightMillimeters) mm" }
        let area = setup.brotherMedia.printableAreaMM(for: setup.brotherModel)
        let fitted = LabelRasterGeometry.fittedSizeMM(layoutHeight: labelSize.heightDots, area: area)
        return String(format: NSLocalizedString("≈ %.0f × %.0f mm sur %@", comment: "Brother printed size"),
                      fitted.width, fitted.height, setup.brotherModel.title)
    }

    private var bitmap: MonochromeBitmap? {
        try? LabelRenderer.render(label, size: labelSize, arrangement: labelArrangement, layoutWidth: layoutWidth)
    }
    private var selectionPreviewLabel: ProductLabel {
        ((try? EAN13.completed(label.ean)) != nil &&
         PriceFormatter.formatted(label.price, currency: label.currency) != nil) ? label : ProductLabel()
    }
    var body: some View {
        NavigationStack {
            Group {
                if let config = gateway.currentConfig() {
                    ProductListView(config: config,
                                    onOpenSettings: { showingSettings = true },
                                    onOpenHistory: { showingHistory = true },
                                    onSelect: { product in
                                        // L'article choisi devient l'étiquette courante → aperçu live.
                                        label = product.label
                                        ebpQuantity = 1
                                    },
                                    impression: { product in impressionTab(for: product) })
                } else {
                    ContentUnavailableView(NSLocalizedString("Gateway non configurée", comment: "Gateway not configured"),
                                           systemImage: "gearshape",
                                           description: Text(NSLocalizedString("Appairez la gateway pour charger les articles.", comment: "")))
                }
            }
            .sheet(isPresented: $showingPrinters) { printerSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .sheet(isPresented: $showingPresentation) { presentationSheet }
            .sheet(isPresented: $showingHistory) { historySheet }
            .alert(NSLocalizedString("Impression", comment: "Print alert"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onChange(of: netum.jobError) { _, error in
                guard let error else { return }
                message = error
                netum.jobError = nil
            }
            .onChange(of: brother.activity) { old, new in
                if old == .printing, new == .idle, brother.statusIsError { message = brother.status }
            }
            .onAppear {
                if LabelSize(rawValue: selectedSize) == nil { selectedSize = LabelSize.standard.rawValue }
                if LabelArrangement(rawValue: selectedArrangement) == nil { selectedArrangement = LabelArrangement.current.rawValue }
                setup.supportedLabels = { model in BrotherPrinterService.supportedLabelIndices(for: model) }
                if isNetum { netum.reconnect() } else if !isBrother { printer.reconnect() }
            }
        }
    }

    /// Onglet « Impression » de la fiche article : l'écran d'impression soigné d'origine
    /// (carte imprimante, présentation graphique, aperçu live), + une carte quantité, + le
    /// bouton Imprimer en direct. Piloté par `label` (l'article sélectionné) → aperçu live.
    private func impressionTab(for product: MappedProduct) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                printerCard
                presentationCard
                previewCard(for: product.label)
                quantityCard
                Button { printCurrentLabel(copies: ebpQuantity) } label: {
                    Label(isPrinting
                          ? NSLocalizedString("Impression…", comment: "Printing progress")
                          : String(format: NSLocalizedString("Imprimer %d étiquette(s)", comment: "Print N labels"), ebpQuantity),
                          systemImage: "printer.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled((try? LabelRenderer.render(product.label, size: labelSize, arrangement: labelArrangement, layoutWidth: layoutWidth)) == nil || isPrinting || !printerReady)
            }
            .onAppear { label = product.label }   // garantit que l'impression utilise cet article
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Carte imprimante (modèle, statut, batterie, bouton Connecter/Changer). Ouvre la modale imprimante.
    private var printerCard: some View {
        HStack {
            if isNetum {
                Image(systemName: "printer.fill")
                    .font(.title3).foregroundStyle(netum.connected ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(netum.connected ? (netum.connectedName ?? "NETUM") : NSLocalizedString("NETUM NT-H861", comment: "NETUM card title")).font(.headline)
                    Text(netum.status).font(.subheadline)
                        .foregroundStyle(netum.statusIsError ? .red : .primary)
                    Text(setup.netum.paper.title + " · " + setup.netum.cut.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if netum.isBusy { ProgressView(value: netum.progress).frame(width: 44) }
                Button(netum.connected ? NSLocalizedString("Changer", comment: "Change printer") : NSLocalizedString("Connecter", comment: "Connect printer")) { openPrinters() }
            } else if isBrother {
                Image(systemName: "printer.fill")
                    .font(.title3).foregroundStyle(printerReady ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(String(format: NSLocalizedString("Brother %@", comment: "Brother printer card title"), setup.brotherModel.title)).font(.headline)
                    Text(brother.target?.displayName ?? NSLocalizedString("Aucune imprimante Brother choisie", comment: "Brother status"))
                        .font(.subheadline)
                    if brother.target != nil || brother.status != NSLocalizedString("Aucune imprimante Brother choisie", comment: "Brother status") {
                        Text(brother.status).font(.caption)
                            .foregroundStyle(brother.statusIsError ? .red : .secondary)
                    }
                }
                Spacer()
                if brother.activity == .printing {
                    Button("Annuler", role: .destructive) { brother.cancelPrint() }
                } else if brother.isBusy { ProgressView() }
                Button(brother.target == nil ? NSLocalizedString("Connecter", comment: "Connect printer") : NSLocalizedString("Changer", comment: "Change printer")) { openPrinters() }
            } else {
                Image(systemName: "printer.fill")
                    .font(.title3).foregroundStyle(printer.connected ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(printer.connected ? printer.displayName : NSLocalizedString("Imprimante", comment: "Printer card title")).font(.headline)
                    Text(printer.status).font(.subheadline)
                    if printer.connected {
                        Label(printer.batteryPercent.map { String(format: NSLocalizedString("Batterie %d %%", comment: "Printer battery"), $0) } ?? NSLocalizedString("Batterie en cours de lecture", comment: "Printer battery"),
                              systemImage: printer.batteryPercent == nil ? "battery.0percent" : "battery.100percent")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(printer.connected ? NSLocalizedString("Changer", comment: "Change printer") : NSLocalizedString("Connecter", comment: "Connect printer")) { openPrinters() }
            }
        }
        .padding(16)
        .modifier(PrintCardStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { openPrinters() }
        .accessibilityAction(named: Text("Réglages de l’imprimante")) { openPrinters() }
    }

    /// Carte « Présentation de l'étiquette » : ouvre le sélecteur de format graphique à miniatures.
    private var presentationCard: some View {
        Button {
            showingPresentation = true
            thumbnailStore.prepare(label: selectionPreviewLabel, size: labelSize,
                                   arrangement: labelArrangement, width: layoutWidth, reset: true)
        } label: {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3).foregroundStyle(.primary)
                VStack(alignment: .leading) {
                    Text("Présentation de l’étiquette").font(.headline)
                    Text("\(labelArrangement.title) · \(labelSize.title) (\(printedSizeText))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(16)
            .modifier(PrintCardStyle())
        }
        .buttonStyle(ResponsiveCardStyle())
    }

    /// Aperçu live de l'étiquette (le bitmap réel qui sera imprimé), rendu depuis l'étiquette donnée.
    private func previewCard(for previewLabel: ProductLabel) -> some View {
        let preview = (try? LabelRenderer.render(previewLabel, size: labelSize, arrangement: labelArrangement, layoutWidth: layoutWidth))
        return VStack(alignment: .leading, spacing: 8) {
            Text("APERÇU DE L’ÉTIQUETTE").font(.headline)
            if let preview, let image = LabelRenderer.preview(preview) {
                Image(uiImage: image).interpolation(.high).resizable()
                    .aspectRatio(CGFloat(preview.width) / CGFloat(preview.height), contentMode: .fit)
                    .background(.white)
                    .overlay(Rectangle().stroke(Color(.separator), lineWidth: 1))
                    .accessibilityLabel("Aperçu de l’étiquette à imprimer")
            } else {
                Text(NSLocalizedString("Aperçu indisponible pour cet article.", comment: "No preview"))
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
        .padding(16)
        .modifier(PrintCardStyle())
    }

    /// Petite carte quantité (−/+), juste au-dessus du bouton Imprimer.
    private var quantityCard: some View {
        HStack {
            Image(systemName: "number.square.fill").font(.title3).foregroundStyle(.primary)
            Text(NSLocalizedString("Quantité", comment: "Quantity")).font(.headline)
            Spacer()
            Stepper(value: $ebpQuantity, in: 1...99) {
                Text("\(ebpQuantity)").font(.headline).monospacedDigit()
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(16)
        .modifier(PrintCardStyle())
    }

    /// Imprime la quantité demandée selon la marque : Netum et Brother en natif (copies),
    /// 5890 en séquence (une étiquette par appel, pilotée par la fin de l'impression).
    private func printCurrentLabel(copies: Int = 1) {
        guard printerReady else { return }
        guard (try? LabelRenderer.render(label, size: labelSize, arrangement: labelArrangement, layoutWidth: layoutWidth)) != nil else {
            message = NSLocalizedString("Article invalide (EAN ou prix).", comment: "Invalid label")
            return
        }
        let count = max(1, copies)
        let entry = PrintedLabel(label: label, size: labelSize, arrangement: labelArrangement,
                                 densityValue: printer.density.rawValue,
                                 leadingFeedDots: printer.leadingFeedDots,
                                 trailingFeedDots: printer.trailingFeedDots,
                                 rotateContent180: printer.rotateContent180,
                                 netum: isNetum ? setup.netum : nil)
        if isNetum {
            let previous = setup.netum.copies
            setup.netum.copies = count
            do { try submit(label, size: labelSize, arrangement: labelArrangement) {
                history.record(entry); setup.netum.copies = previous
            } }
            catch { setup.netum.copies = previous; message = error.localizedDescription }
        } else if isBrother {
            let previous = setup.copies
            setup.copies = count
            do { try submit(label, size: labelSize, arrangement: labelArrangement) {
                history.record(entry); setup.copies = previous
            } }
            catch { setup.copies = previous; message = error.localizedDescription }
        } else {
            // 5890 : une étiquette par appel, en séquence.
            do {
                let bitmap = try LabelRenderer.render(label, size: labelSize, arrangement: labelArrangement)
                printCopiesSequentially(bitmap, remaining: count, onFinished: { history.record(entry) })
            } catch { message = error.localizedDescription }
        }
    }

    /// Imprime `remaining` copies du même bitmap sur la 5890, l'une après l'autre.
    /// `PrinterManager.print` s'auto-verrouille (`guard !printing`) : on enchaîne la copie
    /// suivante quand `printer.printing` repasse à false.
    private func printCopiesSequentially(_ bitmap: MonochromeBitmap, remaining: Int, onFinished: @escaping () -> Void) {
        guard remaining > 0 else { onFinished(); return }
        printer.print(bitmap)
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(15)
            while printer.printing && Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            printCopiesSequentially(bitmap, remaining: remaining - 1, onFinished: onFinished)
        }
    }

    /// Envoie l'étiquette à l'imprimante choisie. La 5890 reçoit le bitmap
    /// de 384 points comme avant ; une Brother reçoit la même mise en page
    /// dessinée hors du fil principal à la résolution de sa tête ; la NETUM
    /// reçoit une disposition 80 mm (576 points) ou celle de la 5890 sur 58 mm.
    private func submit(_ label: ProductLabel, size: LabelSize, arrangement: LabelArrangement,
                        onQueued: (() -> Void)? = nil) throws {
        if isNetum {
            var bitmap = try LabelRenderer.render(label, size: size, arrangement: arrangement, layoutWidth: layoutWidth)
            if setup.netum.rotateContent180 { bitmap = try bitmap.rotated180() }
            netum.print(bitmap: bitmap.bytes, width: bitmap.width, height: bitmap.height,
                        options: setup.netum, onQueued: onQueued)
        } else if isBrother {
            brother.print(job: setup.brotherJob, layoutHeight: size.heightDots, render: { scale in
                try LabelRenderer.grayImage(LabelRenderer.render(label, size: size, arrangement: arrangement, scale: scale))
            }, onSuccess: onQueued)
        } else {
            printer.print(try LabelRenderer.render(label, size: size, arrangement: arrangement), onQueued: onQueued)
        }
    }

    private func restore(_ entry: PrintedLabel) {
        label = entry.label
        selectedSize = entry.size.rawValue
        selectedArrangement = entry.arrangement.rawValue
        if let options = entry.netum {
            // Travail NETUM : ses réglages, sans toucher à ceux de la 5890.
            // Transport Bluetooth gardé tel quel : il dépend de l'appareil.
            var restored = options
            restored.writeWithResponse = setup.netum.writeWithResponse
            restored.packetDelayMS = setup.netum.packetDelayMS
            setup.netum = restored
        } else {
            printer.density = PrintDensity(rawValue: entry.densityValue) ?? .medium
            printer.leadingFeedDots = entry.leadingFeedDots
            printer.trailingFeedDots = entry.trailingFeedDots
            printer.rotateContent180 = entry.rotateContent180
        }
        showingHistory = false
    }

    private func reprint(_ entry: PrintedLabel) {
        guard printerReady else { return }
        restore(entry)
        do {
            _ = try LabelRenderer.render(entry.label, size: entry.size, arrangement: entry.arrangement)
            let copy = PrintedLabel(label: entry.label, size: entry.size, arrangement: entry.arrangement,
                                    densityValue: entry.densityValue, leadingFeedDots: entry.leadingFeedDots,
                                    trailingFeedDots: entry.trailingFeedDots,
                                    rotateContent180: entry.rotateContent180,
                                    netum: isNetum ? setup.netum : nil)
            try submit(entry.label, size: entry.size, arrangement: entry.arrangement) { history.record(copy) }
        } catch { message = error.localizedDescription }
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                if history.entries.isEmpty {
                    ContentUnavailableView("Aucune impression enregistrée", systemImage: "clock.arrow.circlepath",
                                           description: Text("Les étiquettes imprimées apparaîtront ici."))
                }
                ForEach(history.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.label.name).font(.headline)
                        Text("\(entry.printedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.arrangement.title) · \(entry.size.title)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("Restaurer") { restore(entry) }
                                .buttonStyle(.bordered)
                            Button("Réimprimer") { reprint(entry) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!printerReady || isPrinting)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: history.delete)
            }
            .navigationTitle("Historique")
            .toolbar { Button("Fermer") { showingHistory = false } }
        }
    }

    private var presentationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Format").font(.title3.bold())
                    Text(isNetum && layoutWidth == WideLabelLayout.width
                         ? NSLocalizedString("Choisissez la hauteur de la zone imprimée. La largeur est de 72 mm sur rouleau 80 mm.", comment: "Presentation help")
                         : NSLocalizedString("Choisissez la hauteur de la zone imprimée. La largeur reste de 48 mm sur la 5890.", comment: "Presentation help"))
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        ForEach(LabelSize.allCases) { size in
                            Button { selectedSize = size.rawValue } label: {
                                presentationTile(title: size.title, detail: "\(layoutWidthMM) × \(size.heightMillimeters) mm",
                                                 size: size, arrangement: labelArrangement,
                                                 selected: labelSize == size, fullWidth: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Disposition").font(.title3.bold())
                    Text("La miniature est générée avec le même moteur que l’impression.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(LabelArrangement.allCases) { arrangement in
                            Button { selectedArrangement = arrangement.rawValue } label: {
                                presentationTile(title: arrangement.title, detail: "",
                                                 size: labelSize, arrangement: arrangement,
                                                 selected: labelArrangement == arrangement)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Présentation")
            .toolbar { Button("Terminé") { showingPresentation = false } }
        }
    }

    private func presentationTile(title: String, detail: String, size: LabelSize,
                                  arrangement: LabelArrangement, selected: Bool,
                                  fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Color.white
                if let image = thumbnailStore.images[LabelThumbnailStore.key(size: size, arrangement: arrangement, width: layoutWidth)] {
                    Image(uiImage: image).interpolation(.high).resizable()
                        .aspectRatio(CGFloat(layoutWidth) / CGFloat(size.heightDots), contentMode: .fit)
                        .padding(5)
                } else if thumbnailStore.failed.contains(LabelThumbnailStore.key(size: size, arrangement: arrangement, width: layoutWidth)) {
                    Text("Aperçu indisponible").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().tint(.blue)
                }
            }
            .frame(height: fullWidth ? CGFloat(size.heightDots) * 0.82 : 125)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(.separator), lineWidth: 1))
            HStack {
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            }
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(selected ? Color.blue.opacity(0.18) : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.blue : Color.clear, lineWidth: 2))
        .accessibilityLabel("\(title)\(detail.isEmpty ? "" : ", \(detail)")\(selected ? NSLocalizedString(", sélectionné", comment: "Selected tile accessibility suffix") : "")")
    }

    private var printerSheet: some View {
        PrinterSelectionView(printer: printer, setup: setup, brother: brother, netum: netum,
                             canTestPrint: printerReady && !isPrinting,
                             onTestPrint: printTestLabel,
                             onClose: { showingPrinters = false })
    }

    private func openPrinters() {
        if isNetum { netum.scan() } else if !isBrother { printer.scan() }
        showingPrinters = true
    }

    private func printTestLabel() {
        let test = ProductLabel(name: NSLocalizedString("TEST TEXTE 12 18 27", comment: "Calibration label"), category: "5890 · 384 points", shelfReference: NSLocalizedString("RÉF RAYON : 12-04-08", comment: "Calibration label"), productReference: NSLocalizedString("TRAITS | || |||", comment: "Calibration label"), ean: "4006381333931", price: "5,95")
        do {
            try submit(test, size: labelSize, arrangement: labelArrangement)
            showingPrinters = false
        } catch { message = error.localizedDescription }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Imprimante") {
                    LabeledContent("Imprimante", value: isNetum ? "NETUM NT-H861" : isBrother
                                   ? String(format: NSLocalizedString("Brother %@", comment: "Brother printer card title"), setup.brotherModel.title)
                                   : "Pocket 5890")
                    Button("Choisir l’imprimante et le papier") {
                        showingSettings = false
                        // Une feuille ne s'ouvre qu'après la fermeture de la précédente.
                        Task { try? await Task.sleep(for: .milliseconds(450)); openPrinters() }
                    }
                }
                Section("Application") {
                    LabeledContent("Langue de l’application", value: Bundle.main.preferredLocalizations.first == "en" ? "English" : "Français")
                    Button("Choisir la langue dans les réglages iPhone", systemImage: "arrow.up.right.square") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    Text("Le français et l’anglais sont disponibles. iOS applique le choix à toute l’application.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                GatewaySettingsSection(settings: gateway)
            }
            .navigationTitle("Réglages")
            .toolbar { Button("Fermer") { showingSettings = false } }
        }
    }
}

private struct ResponsiveCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PrintCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color(.secondarySystemGroupedBackground),
                           in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
private final class LabelThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failed: Set<String> = []
    private var pending: Set<String> = []
    private var generation = 0

    nonisolated static func key(size: LabelSize, arrangement: LabelArrangement, width: Int) -> String {
        "\(size.rawValue).\(arrangement.rawValue).\(width)"
    }

    func prepare(label: ProductLabel, size: LabelSize, arrangement: LabelArrangement,
                 width: Int, reset: Bool = false) {
        if reset {
            generation += 1
            images.removeAll()
            failed.removeAll()
            pending.removeAll()
        }
        let currentGeneration = generation
        let combinations = LabelSize.allCases.map { ($0, arrangement) }
            + LabelArrangement.allCases.map { (size, $0) }
        let missing = combinations.filter { combination in
            let imageKey = Self.key(size: combination.0, arrangement: combination.1, width: width)
            guard images[imageKey] == nil, !pending.contains(imageKey) else { return false }
            pending.insert(imageKey)
            return true
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            for (imageSize, imageArrangement) in missing {
                let bitmap = try? LabelRenderer.render(label, size: imageSize, arrangement: imageArrangement,
                                                       layoutWidth: width)
                let image = bitmap.flatMap(LabelRenderer.preview)
                let imageKey = Self.key(size: imageSize, arrangement: imageArrangement, width: width)
                await self?.accept(image, for: imageKey, generation: currentGeneration)
            }
        }
    }

    private func accept(_ image: UIImage?, for key: String, generation request: Int) {
        guard generation == request else { return }
        if let image { images[key] = image }
        else { failed.insert(key) }
        pending.remove(key)
    }
}
