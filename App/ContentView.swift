import SwiftUI
import PocketPrinter5890Kit

struct ContentView: View {
    @StateObject private var printer = PrinterManager()
    @State private var label = (UserDefaults.standard.data(forKey: "lastLabel").flatMap { try? JSONDecoder().decode(ProductLabel.self, from: $0) }) ?? ProductLabel()
    @State private var showingPrinters = false
    @State private var showingSettings = false
    @State private var message: String?

    private var bitmap: MonochromeBitmap? { try? LabelRenderer.render(label) }
    private var previewBitmap: MonochromeBitmap? {
        guard let bitmap else { return nil }
        return try? printer.preparedBitmap(bitmap)
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
                    GroupBox("Produit") {
                        VStack(spacing: 10) {
                            field("Nom du produit", text: $label.name)
                            field("Catégorie", text: $label.category)
                            field("Référence rayon", text: $label.shelfReference)
                            field("Référence produit", text: $label.productReference)
                            field("EAN", text: $label.ean, keyboard: .numberPad)
                            if let eanMessage { Text(eanMessage).font(.caption).foregroundStyle(.orange) }
                            field("Prix", text: $label.price, keyboard: .decimalPad)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("APERÇU DE L’ÉTIQUETTE").font(.headline)
                        if let previewBitmap, let image = LabelRenderer.preview(previewBitmap) {
                            Image(uiImage: image).interpolation(.none).resizable()
                                .aspectRatio(50.0 / 30.0, contentMode: .fit)
                                .background(.white)
                                .accessibilityLabel("Aperçu de l’étiquette à imprimer")
                        } else {
                            Text("Saisissez un EAN et un prix valides pour voir l’aperçu.")
                                .frame(maxWidth: .infinity, minHeight: 170)
                        }
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(printer.connected ? "5890" : "Imprimante") .font(.headline)
                            Text(printer.status).font(.subheadline)
                        }
                        Spacer()
                        Button(printer.connected ? "Changer" : "Connecter") { printer.scan(); showingPrinters = true }
                    }
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
                .padding()
            }
            .navigationTitle("PRODUCT LABEL 5890")
            .toolbar { Button("Réglages", systemImage: "gearshape") { showingSettings = true } }
            .sheet(isPresented: $showingPrinters) { printerSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .alert("Impression", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onChange(of: label) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "lastLabel") }
            }
            .onAppear { printer.reconnect() }
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text).textFieldStyle(.roundedBorder).keyboardType(keyboard)
            .textInputAutocapitalization(.sentences)
    }

    private var printerSheet: some View {
        NavigationStack {
            List {
                if printer.devices.isEmpty { Text(printer.status) }
                ForEach(printer.devices.filter(\.isLikelyL13)) { device in
                    Button("\(device.name) (\(device.rssi) dBm)") {
                        printer.connect(device)
                        showingPrinters = false
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
                Picker("Densité", selection: $printer.density) {
                    ForEach(PrintDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
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
                Toggle("Tourner l’impression de 180°", isOn: $printer.rotateContent180)
                Text("L’aperçu montre le sens imprimé. Retournez le ticket après découpe pour lire l’étiquette avec le grand blanc en bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Section("Calibration") {
                    Button("Imprimer une étiquette de test") {
                        let test = ProductLabel(name: "TEST TEXTE 12 18 27", category: "5890 · 384 points", shelfReference: "RÉF RAYON : 12-04-08", productReference: "TRAITS | || |||", ean: "4006381333931", price: "5,95")
                        do {
                            printer.print(try LabelRenderer.render(test))
                            showingSettings = false
                            if !printer.connected { printer.scan(); showingPrinters = true }
                        } catch { message = error.localizedDescription }
                    }
                }
                if printer.connected { Button("Déconnecter") { printer.disconnect() } }
            }
            .navigationTitle("Réglages")
            .toolbar { Button("Fermer") { showingSettings = false } }
        }
    }
}
