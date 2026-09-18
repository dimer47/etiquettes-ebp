import SwiftUI
import PocketPrinter5890Kit

struct ContentView: View {
    @StateObject private var printer = PrinterManager()
    @StateObject private var thumbnailStore = LabelThumbnailStore()
    @State private var label = (UserDefaults.standard.data(forKey: "lastLabel").flatMap { try? JSONDecoder().decode(ProductLabel.self, from: $0) }) ?? ProductLabel()
    @State private var showingPrinters = false
    @State private var showingSettings = false
    @State private var showingPresentation = false
    @State private var showingScanner = false
    @State private var message: String?
    @State private var selectedPage = 0
    @State private var categories = (UserDefaults.standard.array(forKey: "savedCategories") as? [String]) ?? ["Peinture / Aérosols"]
    @State private var newCategory = ""
    @AppStorage("labelSize") private var selectedSize = LabelSize.standard.rawValue
    @AppStorage("labelArrangement") private var selectedArrangement = LabelArrangement.current.rawValue

    private var labelSize: LabelSize { LabelSize(rawValue: selectedSize) ?? .standard }
    private var labelArrangement: LabelArrangement { LabelArrangement(rawValue: selectedArrangement) ?? .current }

    private var bitmap: MonochromeBitmap? {
        try? LabelRenderer.render(label, size: labelSize, arrangement: labelArrangement)
    }
    private var selectionPreviewLabel: ProductLabel {
        ((try? EAN13.completed(label.ean)) != nil &&
         PriceFormatter.formatted(label.price, currency: label.currency) != nil) ? label : ProductLabel()
    }
    private var eanMessage: String? {
        do {
            let completed = try EAN13.completed(label.ean)
            return completed == label.ean ? nil : "Chiffre de contrôle calculé : \(completed)"
        } catch EAN13Error.invalidChecksum { return "Chiffre de contrôle EAN incorrect" }
        catch { return "Saisir 12 ou 13 chiffres EAN" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        pageButton("Produit", icon: "square.and.pencil", page: 0)
                        pageButton("Impression", icon: "printer", page: 1)
                    }
                    if selectedPage == 0 {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Informations produit").font(.title3.bold())
                        VStack(alignment: .leading, spacing: 14) {
                            field("Nom du produit", text: $label.name)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Catégorie").font(.subheadline.bold())
                                TextField("Catégorie", text: $label.category)
                                    .modifier(ProductInputStyle())
                                HStack {
                                    Menu {
                                        if categories.isEmpty { Text("Aucune catégorie enregistrée") }
                                        ForEach(categories, id: \.self) { category in
                                            Button(category) { label.category = category }
                                        }
                                    } label: {
                                        Label("Choisir", systemImage: "list.bullet")
                                    }
                                    .accessibilityLabel("Choisir une catégorie")
                                    .buttonStyle(.bordered)
                                    Button {
                                        categories = CategoryLibrary.adding(label.category, to: categories)
                                    } label: {
                                        Label("Enregistrer", systemImage: "plus")
                                    }
                                    .accessibilityLabel("Enregistrer cette catégorie")
                                    .buttonStyle(.bordered)
                                    .disabled(CategoryLibrary.adding(label.category, to: categories) == categories)
                                }
                            }
                            field("Référence rayon", text: $label.shelfReference)
                            field("Référence produit", text: $label.productReference)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Code-barres EAN-13").font(.subheadline.bold())
                                TextField("13 chiffres", text: $label.ean)
                                    .keyboardType(.numberPad)
                                    .modifier(ProductInputStyle())
                                Button { showingScanner = true } label: {
                                    Label("Scanner un code", systemImage: "barcode.viewfinder")
                                }
                                .buttonStyle(.bordered)
                            }
                            if let eanMessage { Text(eanMessage).font(.caption).foregroundStyle(.orange) }
                            field("Libellé du prix", text: $label.priceCaption)
                            HStack(alignment: .bottom) {
                                field("Prix de vente TTC", text: $label.price, keyboard: .decimalPad)
                                Picker("Devise", selection: $label.currency) {
                                    ForEach(LabelCurrency.allCases) { currency in
                                        Text("\(currency.symbol) \(currency.rawValue)").tag(currency)
                                    }
                                }
                                .labelsHidden()
                                .accessibilityLabel("Devise")
                                .frame(width: 110)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    Button("Voir l’aperçu") { selectedPage = 1 }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                    HStack {
                        Image(systemName: "printer.fill")
                            .font(.title3).foregroundStyle(printer.connected ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(printer.connected ? printer.displayName : "Imprimante").font(.headline)
                            Text(printer.status).font(.subheadline)
                            if printer.connected {
                                Label(printer.batteryPercent.map { "Batterie \($0) %" } ?? "Batterie en cours de lecture",
                                      systemImage: printer.batteryPercent == nil ? "battery.0percent" : "battery.100percent")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(printer.connected ? "Changer" : "Connecter") { printer.scan(); showingPrinters = true }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        showingPresentation = true
                        thumbnailStore.prepare(label: selectionPreviewLabel, size: labelSize,
                                               arrangement: labelArrangement, reset: true)
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.title3).foregroundStyle(.primary)
                            VStack(alignment: .leading) {
                                Text("Présentation de l’étiquette").font(.headline)
                                Text("\(labelArrangement.title) · \(labelSize.title) (48 × \(labelSize.heightMillimeters) mm)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 1))
                    }
                    .buttonStyle(ResponsiveCardStyle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text("APERÇU DE L’ÉTIQUETTE").font(.headline)
                        if let bitmap, let image = LabelRenderer.preview(bitmap) {
                            Image(uiImage: image).interpolation(.high).resizable()
                                .aspectRatio(CGFloat(bitmap.width) / CGFloat(bitmap.height), contentMode: .fit)
                                .background(.white)
                                .overlay(Rectangle().stroke(Color(.separator), lineWidth: 1))
                                .accessibilityLabel("Aperçu de l’étiquette à imprimer")
                        } else {
                            Text("Saisissez un EAN et un prix valides pour voir l’aperçu.")
                                .frame(maxWidth: .infinity, minHeight: 170)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        guard let bitmap else { return }
                        printer.print(bitmap)
                        if !printer.connected { showingPrinters = true }
                    } label: {
                        Label(printer.printing ? "Impression…" : "Imprimer", systemImage: "printer.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(bitmap == nil || printer.printing)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PRODUCT LABEL 5890")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Réglages", systemImage: "gearshape") { showingSettings = true } }
            .sheet(isPresented: $showingPrinters) { printerSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .sheet(isPresented: $showingPresentation) { presentationSheet }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { code in
                    label.ean = code
                    showingScanner = false
                }
            }
            .alert("Impression", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onChange(of: label) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "lastLabel") }
            }
            .onChange(of: categories) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "savedCategories")
            }
            .onChange(of: selectedSize) { _, _ in
                if showingPresentation {
                    thumbnailStore.prepare(label: selectionPreviewLabel, size: labelSize, arrangement: labelArrangement)
                }
            }
            .onChange(of: selectedArrangement) { _, _ in
                if showingPresentation {
                    thumbnailStore.prepare(label: selectionPreviewLabel, size: labelSize, arrangement: labelArrangement)
                }
            }
            .onAppear {
                if LabelSize(rawValue: selectedSize) == nil { selectedSize = LabelSize.standard.rawValue }
                if LabelArrangement(rawValue: selectedArrangement) == nil { selectedArrangement = LabelArrangement.current.rawValue }
                printer.reconnect()
            }
        }
    }

    private var presentationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Format").font(.title3.bold())
                    Text("Choisissez la hauteur de la zone imprimée. La largeur reste de 48 mm sur la 5890.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        ForEach(LabelSize.allCases) { size in
                            Button { selectedSize = size.rawValue } label: {
                                presentationTile(title: size.title, detail: "48 × \(size.heightMillimeters) mm",
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
                if let image = thumbnailStore.images[LabelThumbnailStore.key(size: size, arrangement: arrangement)] {
                    Image(uiImage: image).interpolation(.high).resizable()
                        .aspectRatio(CGFloat(LabelRenderer.width) / CGFloat(size.heightDots), contentMode: .fit)
                        .padding(5)
                } else if thumbnailStore.failed.contains(LabelThumbnailStore.key(size: size, arrangement: arrangement)) {
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
        .accessibilityLabel("\(title)\(detail.isEmpty ? "" : ", \(detail)")\(selected ? ", sélectionné" : "")")
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            TextField(title, text: text).keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                .modifier(ProductInputStyle())
        }
    }

    private func pageButton(_ title: String, icon: String, page: Int) -> some View {
        let selected = selectedPage == page
        return Button { selectedPage = page } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.blue : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : Color(.separator), lineWidth: 1))
        }
        .buttonStyle(ResponsiveCardStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var printerSheet: some View {
        NavigationStack {
            List {
                if printer.devices.isEmpty { Text(printer.status) }
                ForEach(printer.devices.filter(\.isLikelyL13)) { device in
                    Button {
                        printer.connect(device)
                        showingPrinters = false
                    } label: {
                        VStack(alignment: .leading) {
                            let alias = UserDefaults.standard.string(forKey: "printerAlias.\(device.id.uuidString)") ?? ""
                            Text(alias.isEmpty ? device.name : alias).font(.headline)
                            Text(alias.isEmpty ? "Signal : \(device.rssi) dBm" : "\(device.name) · \(device.rssi) dBm")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Choisir la 5890")
            .toolbar { Button("Fermer") { showingPrinters = false } }
        }
        .presentationDetents([.medium, .large])
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Imprimante") {
                    if printer.connected {
                        Text(printer.connectedDeviceName ?? "Pocket Printer 5890")
                        TextField("Nom personnalisé", text: $printer.printerAlias)
                        if let battery = printer.batteryPercent {
                            Label("Batterie : \(battery) %", systemImage: "battery.100percent")
                        } else {
                            Text("Niveau de batterie en cours de lecture")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Aucune imprimante connectée").foregroundStyle(.secondary)
                    }
                }
                Section("Impression thermique") {
                Picker("Densité", selection: $printer.density) {
                    ForEach(PrintDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                Picker("Avance avant impression", selection: $printer.leadingFeedDots) {
                    Text("0 mm").tag(0)
                    Text("1 mm").tag(8)
                    Text("2 mm").tag(16)
                    Text("3 mm").tag(24)
                    Text("5 mm").tag(40)
                    Text("10 mm").tag(80)
                }
                Picker("Avance après impression", selection: $printer.trailingFeedDots) {
                    Text("10 mm").tag(80)
                    Text("12 mm").tag(96)
                    Text("13 mm").tag(104)
                    Text("14 mm").tag(112)
                    Text("15 mm").tag(120)
                    Text("16 mm").tag(128)
                    Text("20 mm").tag(160)
                }
                Text("13 mm ajoute environ 3 mm de papier blanc après le prix par rapport au réglage initial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("L’avance avant impression vaut 0 mm par défaut. Elle ajoute du papier avant le premier point imprimé.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Tourner l’impression de 180°", isOn: $printer.rotateContent180)
                Text("L’aperçu reste à l’endroit. Retournez le ticket après découpe pour lire l’étiquette avec le grand blanc en bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Section("Test et connexion") {
                    Button("Imprimer une étiquette de test") {
                        let test = ProductLabel(name: "TEST TEXTE 12 18 27", category: "5890 · 384 points", shelfReference: "RÉF RAYON : 12-04-08", productReference: "TRAITS | || |||", ean: "4006381333931", price: "5,95")
                        do {
                            printer.print(try LabelRenderer.render(test, size: labelSize, arrangement: labelArrangement))
                            showingSettings = false
                            if !printer.connected { printer.scan(); showingPrinters = true }
                        } catch { message = error.localizedDescription }
                    }
                    if printer.connected { Button("Déconnecter") { printer.disconnect() } }
                }
                Section("Catégories enregistrées") {
                    HStack {
                        TextField("Nouvelle catégorie", text: $newCategory)
                        Button("Ajouter", systemImage: "plus") {
                            categories = CategoryLibrary.adding(newCategory, to: categories)
                            newCategory = ""
                        }
                        .disabled(CategoryLibrary.adding(newCategory, to: categories) == categories)
                    }
                    if categories.isEmpty { Text("Aucune catégorie enregistrée").foregroundStyle(.secondary) }
                    ForEach(categories, id: \.self) { category in
                        Text(category)
                    }
                    .onDelete { offsets in categories.remove(atOffsets: offsets) }
                }
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

private struct ProductInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 1))
    }
}

@MainActor
private final class LabelThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failed: Set<String> = []
    private var pending: Set<String> = []
    private var generation = 0

    nonisolated static func key(size: LabelSize, arrangement: LabelArrangement) -> String {
        "\(size.rawValue).\(arrangement.rawValue)"
    }

    func prepare(label: ProductLabel, size: LabelSize, arrangement: LabelArrangement, reset: Bool = false) {
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
            let imageKey = Self.key(size: combination.0, arrangement: combination.1)
            guard images[imageKey] == nil, !pending.contains(imageKey) else { return false }
            pending.insert(imageKey)
            return true
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            for (imageSize, imageArrangement) in missing {
                let bitmap = try? LabelRenderer.render(label, size: imageSize, arrangement: imageArrangement)
                let image = bitmap.flatMap(LabelRenderer.preview)
                let imageKey = Self.key(size: imageSize, arrangement: imageArrangement)
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
