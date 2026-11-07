import SwiftUI

/// Volet NETUM de l'écran Imprimante, dans l'ordre : 2. papier,
/// 3. coupe et copies, 4. fin d'impression, 5. transport, puis connexion.
struct NetumSections: View {
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var netum: NetumPrinterService
    let onConnected: () -> Void

    var body: some View {
        Section {
            Picker("Rouleau", selection: $setup.netum.paper) {
                ForEach(NetumPaper.allCases) { Text($0.title).tag($0) }
            }
            if setup.netum.paper == .mm58 {
                Stepper(value: $setup.netum.leftMarginDots, in: 0...192, step: 8) {
                    LabeledContent("Décalage à gauche", value: millimeters(setup.netum.leftMarginDots))
                }
            }
        } header: {
            Text("2. Papier")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if setup.netum.paper == .mm80 {
                    Text("72 mm imprimables. Les dispositions 80 mm se choisissent dans Présentation de l’étiquette.")
                } else {
                    Text("48 mm imprimables : mêmes dispositions que la 5890. Placez le séparateur de papier fourni.")
                    Text("Le décalage pousse l’étiquette vers la droite si le rouleau n’est pas calé à gauche de la tête.")
                }
                Text("Papier continu uniquement : l’imprimante ne détecte pas les étiquettes prédécoupées.")
            }
        }

        Section {
            Picker("Coupe", selection: $setup.netum.cut) {
                ForEach(NetumCut.allCases) { Text($0.title).tag($0) }
            }
            Picker(LocalizedStringKey(setup.netum.cut == .none ? "Avance après impression" : "Marge avant la coupe"),
                   selection: $setup.netum.trailingFeedDots) {
                ForEach([0, 8, 16, 24, 40, 80, 120, 160], id: \.self) { Text(millimeters($0)).tag($0) }
            }
            Picker("Avance avant impression", selection: $setup.netum.leadingFeedDots) {
                ForEach([0, 8, 16, 24, 40, 80], id: \.self) { Text(millimeters($0)).tag($0) }
            }
            Stepper(value: $setup.netum.copies, in: NetumOptions.copiesRange) {
                LabeledContent("Exemplaires", value: "\(setup.netum.copies)")
            }
        } header: {
            Text("3. Coupe et copies")
        } footer: {
            Text("Chaque exemplaire est coupé. L’imprimante amène d’elle-même la fin de l’étiquette sous la lame ; la marge ajoute du blanc après le prix.")
        }

        Section {
            Toggle("Bip en fin d’impression", isOn: $setup.netum.beep)
            if setup.netum.beep {
                Stepper(value: $setup.netum.beepCount, in: NetumOptions.beepRange) {
                    LabeledContent("Nombre de bips", value: "\(setup.netum.beepCount)")
                }
                Stepper(value: $setup.netum.beepDuration, in: NetumOptions.beepRange) {
                    LabeledContent("Durée", value: "\(setup.netum.beepDuration * 50) ms")
                }
                Button("Essayer le bip") {
                    netum.testBeep(count: setup.netum.beepCount, duration: setup.netum.beepDuration)
                }
                .disabled(!netum.connected || netum.isBusy)
            }
            Toggle("Tourner l’impression de 180°", isOn: $setup.netum.rotateContent180)
            Toggle("Vérifier papier et capot avant d’imprimer", isOn: $setup.netum.checkStatusBeforePrint)
        } header: {
            Text("4. Fin d’impression")
        } footer: {
            Text("La vérification bloque l’impression si le capot est ouvert, s’il n’y a plus de papier ou si le massicot est en erreur.")
        }

        Section {
            Toggle("Écriture avec accusé", isOn: $setup.netum.writeWithResponse)
            Stepper(value: $setup.netum.packetDelayMS, in: NetumOptions.packetDelayRange, step: 5) {
                LabeledContent("Pause entre paquets", value: "\(setup.netum.packetDelayMS) ms")
            }
        } header: {
            Text("5. Bluetooth")
        } footer: {
            Text("À activer seulement si des lignes manquent ou si l’impression s’arrête en route : plus lent, plus sûr.")
        }

        if netum.connected {
            Section("Imprimante connectée") {
                Text(netum.connectedName ?? "NETUM")
                LabeledContent("État") {
                    Text(netum.status).foregroundStyle(netum.statusIsError ? .red : .secondary)
                }
                Button("Lire l’état", systemImage: "arrow.clockwise") { netum.refreshStatus() }
                    .disabled(netum.isBusy)
                Button("Déconnecter", role: .destructive) { netum.disconnect() }
            }
        }

        Section {
            if netum.devices.isEmpty { Text(netum.status) }
            ForEach(netum.devices) { device in
                Button {
                    netum.connect(device)
                    onConnected()
                } label: {
                    VStack(alignment: .leading) {
                        Text(device.name).font(.headline)
                        Text(String(format: NSLocalizedString("Signal : %d dBm", comment: "Printer signal"), device.rssi))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Afficher tous les appareils", isOn: $netum.showAllDevices)
                .onChange(of: netum.showAllDevices) { _, _ in netum.applyDeviceFilter() }
            Button("Rechercher à nouveau", systemImage: "arrow.clockwise") { netum.scan() }
        } header: {
            Text("NETUM à proximité")
        } footer: {
            Text("La NETUM n’apparaît pas dans les réglages Bluetooth de l’iPhone : la connexion se fait ici. Si elle n’est pas listée, affichez tous les appareils.")
        }
    }

    private func millimeters(_ dots: Int) -> String {
        String(format: NSLocalizedString("%d mm", comment: "Millimeters"), dots / 8)
    }
}
