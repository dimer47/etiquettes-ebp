import SwiftUI
import PocketPrinter5890Kit

/// Écran « Imprimante », dans l'ordre : 1. imprimante (Pocket 5890 ou
/// Brother, puis le modèle), 2. papier compatible, 3. coupe et copies,
/// puis la connexion. Ouvert par le bouton Connecter / Changer.
struct PrinterSelectionView: View {
    @ObservedObject var printer: PrinterManager
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Imprimante", selection: $setup.brand) {
                        Text("Pocket 5890").tag(PrinterBrand.pocket5890)
                        Text("Brother").tag(PrinterBrand.brother)
                    }
                    .pickerStyle(.segmented)
                    if setup.brand == .brother {
                        NavigationLink {
                            BrotherModelPicker(selection: $setup.brotherModel)
                        } label: {
                            LabeledContent("Modèle", value: setup.brotherModel.title)
                        }
                        ConnectionBadges(model: setup.brotherModel)
                    }
                } header: {
                    Text("1. Imprimante")
                } footer: {
                    if setup.brand == .pocket5890 {
                        Text("SilverCrest / Tronic 5890 en Bluetooth LE, tête de 384 points.")
                    } else {
                        Text("Brother Print SDK : Bluetooth LE ou Wi-Fi selon le modèle.")
                    }
                }

                if setup.brand == .pocket5890 {
                    pocketSections
                } else {
                    BrotherPaperSection(setup: setup, brother: brother)
                    BrotherCutSection(setup: setup)
                    BrotherConnectionSections(setup: setup, brother: brother)
                }
            }
            .navigationTitle("Imprimante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer", action: onClose) }
            .onChange(of: setup.brand) { _, brand in
                if brand == .pocket5890 { printer.scan() } else { brother.cancelSearch() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var pocketSections: some View {
        Section("2. Papier") {
            Text("Rouleau ticket 58 mm continu (48 mm imprimables)")
            Text("Le format de l’étiquette se choisit dans Présentation de l’étiquette.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Pocket 5890 à proximité") {
            if printer.devices.filter(\.isLikelyL13).isEmpty { Text(printer.status) }
            ForEach(printer.devices.filter(\.isLikelyL13)) { device in
                Button {
                    printer.connect(device)
                    onClose()
                } label: {
                    VStack(alignment: .leading) {
                        let alias = UserDefaults.standard.string(forKey: "printerAlias.\(device.id.uuidString)") ?? ""
                        Text(alias.isEmpty ? device.name : alias).font(.headline)
                        Text(alias.isEmpty ? String(format: NSLocalizedString("Signal : %d dBm", comment: "Printer signal"), device.rssi) : "\(device.name) · \(device.rssi) dBm")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Rechercher à nouveau", systemImage: "arrow.clockwise") { printer.scan() }
        }
    }
}

// MARK: - Modèle

/// Interfaces documentées pour le modèle, et ce que l'app sait utiliser.
struct ConnectionBadges: View {
    let model: BrotherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(BrotherConnection.allCases) { connection in
                    if model.connections.contains(connection) {
                        Text(connection.title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(model.appConnections.contains(connection)
                                                       ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.15)))
                    }
                }
            }
            if model.appConnections.isEmpty {
                Text("Aucune connexion gérée par l’app pour ce modèle (USB ou Bluetooth Classic MFi seulement).")
                    .font(.caption).foregroundStyle(.orange)
            } else if !model.supportsBLE {
                Text("Pas de Bluetooth LE sur ce modèle : connexion en Wi-Fi.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct BrotherModelPicker: View {
    @Binding var selection: BrotherModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyBLE = false

    var body: some View {
        List {
            Toggle("Bluetooth LE seulement", isOn: $onlyBLE)
            ForEach(BrotherSeries.allCases) { series in
                let models = BrotherModel.allCases.filter { model in
                    model.series == series && (!onlyBLE || model.supportsBLE)
                        && (query.isEmpty || model.rawValue.localizedCaseInsensitiveContains(query))
                }
                if !models.isEmpty {
                    Section(series.title) {
                        ForEach(models) { model in
                            Button {
                                selection = model
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.title).foregroundStyle(.primary)
                                        Text(model.appConnections.isEmpty
                                             ? NSLocalizedString("Pas de connexion iOS gérée", comment: "Brother model list")
                                             : model.appConnections.map(\.title).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Modèle Brother")
    }
}

// MARK: - 2. Papier

struct BrotherPaperSection: View {
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService

    var body: some View {
        Section {
            let model = setup.brotherModel
            switch model.series.paperSource {
            case .customPaper:
                CustomPaperEditor(model: model, media: $setup.brotherMedia)
            case .qlLabel, .ptTape:
                Picker(LocalizedStringKey(model.series == .ql ? "Étiquette DK" : "Ruban"), selection: labelBinding) {
                    ForEach(BrotherPrinterService.supportedLabels(for: model)) { Text($0.title).tag($0.index) }
                }
            case .pjSheet:
                Picker("Format", selection: sheetBinding) {
                    ForEach(BrotherSheet.allCases) { Text($0.title).tag($0) }
                }
            case .fixedByModel:
                Text(String(format: NSLocalizedString("Format imposé par le modèle : %@", comment: "MW paper"),
                            setup.brotherModel.mwSheetMM?.width == 74 ? "A7" : "A6"))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("2. Papier")
        } footer: {
            Text("Le papier proposé dépend du modèle choisi. Il doit correspondre au rouleau chargé, et l’imprimante doit être calibrée pour lui.")
        }
    }

    private var labelBinding: Binding<Int> {
        Binding(
            get: {
                switch setup.brotherMedia {
                case let .qlLabel(index), let .ptTape(index): return index
                default: return 0
                }
            },
            set: { setup.brotherMedia = setup.brotherModel.series == .ql ? .qlLabel($0) : .ptTape($0) }
        )
    }

    private var sheetBinding: Binding<BrotherSheet> {
        Binding(
            get: { if case let .sheet(sheet) = setup.brotherMedia { return sheet }; return .a4 },
            set: { setup.brotherMedia = .sheet($0) }
        )
    }
}

/// Continu, prédécoupé ou marque noire, pour les TD et RJ.
struct CustomPaperEditor: View {
    let model: BrotherModel
    @Binding var media: BrotherMedia
    private static let customID = "custom"

    var body: some View {
        Picker("Format", selection: presetBinding) {
            ForEach(model.paperPresets) { Text(title(for: $0)).tag($0.id) }
            Text("Personnalisé").tag(Self.customID)
        }
        Picker("Type", selection: kindBinding) {
            Text("Continu").tag(BrotherPaper.Kind.roll)
            Text("Prédécoupé").tag(BrotherPaper.Kind.dieCut)
            Text("Marque noire").tag(BrotherPaper.Kind.markRoll)
        }
        .pickerStyle(.segmented)
        Stepper(value: binding(\.widthMM), in: 10...model.maxPaperWidthMM, step: 1) {
            Text(String(format: NSLocalizedString("Largeur : %@ mm", comment: "Paper"), BrotherPaper.format(paper.widthMM)))
        }
        if paper.kind.hasFixedLength {
            Stepper(value: binding(\.lengthMM), in: 10...1000, step: 1) {
                Text(String(format: NSLocalizedString("Longueur : %@ mm", comment: "Paper"), BrotherPaper.format(paper.lengthMM)))
            }
        }
        if paper.kind == .dieCut {
            Stepper(value: binding(\.gapMM), in: 0...20, step: 0.5) {
                Text(String(format: NSLocalizedString("Espace entre étiquettes : %@ mm", comment: "Paper"), BrotherPaper.format(paper.gapMM)))
            }
        }
        if paper.kind == .markRoll {
            Stepper(value: binding(\.markOffsetMM), in: 0...max(0, paper.lengthMM), step: 0.5) {
                Text(String(format: NSLocalizedString("Position de la marque : %@ mm", comment: "Paper"), BrotherPaper.format(paper.markOffsetMM)))
            }
            Stepper(value: binding(\.markLengthMM), in: 1...20, step: 0.5) {
                Text(String(format: NSLocalizedString("Hauteur de la marque : %@ mm", comment: "Paper"), BrotherPaper.format(paper.markLengthMM)))
            }
            Text("La marque noire est imprimée au dos du rouleau ; sa position se mesure depuis le début de l’étiquette.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Stepper(value: binding(\.marginMM), in: 0...10, step: 0.5) {
            Text(String(format: NSLocalizedString("Marges : %@ mm", comment: "Paper"), BrotherPaper.format(paper.marginMM)))
        }
    }

    private var paper: BrotherPaper {
        if case let .custom(paper) = media { return paper }
        return model.paperPresets.first ?? .roll(widthMM: 58)
    }

    private func title(for paper: BrotherPaper) -> String {
        let width = BrotherPaper.format(paper.widthMM)
        let length = BrotherPaper.format(paper.lengthMM)
        switch paper.kind {
        case .roll: return String(format: NSLocalizedString("Continu %@ mm", comment: "Paper preset"), width)
        case .dieCut: return String(format: NSLocalizedString("Prédécoupé %@ × %@ mm", comment: "Paper preset"), width, length)
        case .markRoll: return String(format: NSLocalizedString("Marque noire %@ × %@ mm", comment: "Paper preset"), width, length)
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { model.paperPresets.contains(paper) ? paper.id : Self.customID },
            set: { id in
                if let preset = model.paperPresets.first(where: { $0.id == id }) { media = .custom(preset) }
            }
        )
    }

    private var kindBinding: Binding<BrotherPaper.Kind> {
        Binding(get: { paper.kind }, set: { media = .custom(paper.converted(to: $0)) })
    }

    private func binding(_ keyPath: WritableKeyPath<BrotherPaper, Double>) -> Binding<Double> {
        Binding(
            get: { paper[keyPath: keyPath] },
            set: { value in
                var updated = paper
                updated[keyPath: keyPath] = value
                updated.markOffsetMM = min(updated.markOffsetMM, max(0, updated.lengthMM))
                media = .custom(updated)
            }
        )
    }
}

// MARK: - 3. Coupe et copies

struct BrotherCutSection: View {
    @ObservedObject var setup: PrinterSetup

    var body: some View {
        let cutter = setup.brotherModel.series.cutter
        Section {
            if cutter.isControllable {
                Toggle("Coupe après chaque page", isOn: $setup.cut.autoCut)
                if cutter.supportsCutEvery, setup.cut.autoCut {
                    Stepper(value: $setup.cut.cutEveryPages, in: 1...255) {
                        Text(String(format: NSLocalizedString("Couper toutes les %d pages", comment: "Cut"), setup.cut.cutEveryPages))
                    }
                }
                if cutter.supportsCutAtEnd {
                    Toggle("Coupe après la dernière page", isOn: $setup.cut.cutAtEnd)
                }
            }
            Stepper(value: $setup.copies, in: 1...99) {
                Text(String(format: NSLocalizedString("Copies : %d", comment: "Copies"), setup.copies))
            }
        } header: {
            Text("3. Coupe et copies")
        } footer: {
            switch cutter {
            case .optionalUnit:
                Text("Le massicot des TD est une option matérielle. Sans massicot installé, aucune coupe n’a lieu : laissez la coupe désactivée.")
            case .builtIn:
                Text("Massicot intégré.")
            case .autoCutOnly:
                Text("Sur les P-touch, seule la coupe automatique est pilotable ; certains modèles n’ont qu’une coupe manuelle.")
            case .none:
                Text("Pas de coupe pilotable sur cette série : détachez l’étiquette à la main.")
            }
        }
    }
}

// MARK: - Connexion Brother

struct BrotherConnectionSections: View {
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService
    @AppStorage("brother.connection") private var connectionRaw = BrotherConnection.ble.rawValue
    @AppStorage("brother.lastIP") private var manualAddress = ""

    var body: some View {
        let model = setup.brotherModel
        let connection = effectiveConnection(for: model)

        Section {
            if !BrotherPrinterService.isSDKAvailable {
                Label("Brother Print SDK absent", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Ajoutez BRLMPrinterKit.xcframework au projet Xcode (voir docs/BROTHER_FR.md).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.appConnections.count > 1 {
                Picker("Connexion", selection: $connectionRaw) {
                    ForEach(model.appConnections) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            if model.appConnections.isEmpty {
                Text("Aucune connexion gérée par l’app pour ce modèle (USB ou Bluetooth Classic MFi seulement).")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button(LocalizedStringKey(brother.activity == .searching ? "Arrêter la recherche" : "Rechercher")) {
                        if brother.activity == .searching { brother.cancelSearch() } else { brother.search(connection) }
                    }
                    .disabled(!BrotherPrinterService.isSDKAvailable
                              || (brother.activity != .idle && brother.activity != .searching))
                    if brother.isBusy {
                        Spacer()
                        ProgressView()
                    }
                }
                if connection == .wifi {
                    HStack {
                        TextField("Adresse IP", text: $manualAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Utiliser") { brother.useAddress(manualAddress) }
                            .disabled(manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            Text(brother.status)
                .font(.callout)
                .foregroundStyle(brother.statusIsError ? .red : .secondary)
        } header: {
            Text("Connexion")
        }

        if !brother.found.isEmpty {
            Section("Imprimantes trouvées") {
                ForEach(brother.found) { found in
                    Button { brother.select(found) } label: {
                        TargetRow(printer: found, isSelected: found == brother.target)
                    }
                }
            }
        }

        if let target = brother.target {
            Section("Imprimante Brother choisie") {
                TargetRow(printer: target, isSelected: true)
                if !model.appConnections.contains(target.connection) {
                    Text(String(format: NSLocalizedString("%@ n’est pas disponible sur %@ : relancez une recherche.", comment: "Brother connection"),
                                target.connection.title, model.title))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let detected = brother.detectedModel, detected != model {
                    Text(String(format: NSLocalizedString("L’imprimante annonce %@ alors que %@ est choisi.", comment: "Brother model mismatch"),
                                detected.title, model.title))
                        .font(.caption).foregroundStyle(.orange)
                    Button(String(format: NSLocalizedString("Basculer sur %@", comment: "Brother model mismatch"), detected.title)) {
                        setup.brotherModel = detected
                    }
                }
                Button("Tester la connexion et lire l’état") { brother.checkStatus(selectedModel: model) }
                    .disabled(brother.isBusy || !BrotherPrinterService.isSDKAvailable)
                Button("Oublier cette imprimante", role: .destructive) { brother.forget() }
                    .disabled(brother.isBusy)
            }
        }
    }

    /// Interface choisie, ramenée à une interface disponible sur le modèle.
    private func effectiveConnection(for model: BrotherModel) -> BrotherConnection {
        let chosen = BrotherConnection(rawValue: connectionRaw) ?? .ble
        return model.appConnections.contains(chosen) ? chosen : (model.appConnections.first ?? .ble)
    }
}

private struct TargetRow: View {
    let printer: BrotherTarget
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.displayName).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text("\(printer.connection.title) · \(printer.address)")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }
}
