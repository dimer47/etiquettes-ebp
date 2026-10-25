import SwiftUI

/// Journal du SDK Brother : recherche, connexion, impressions, infos.
/// Repris de TD Print Studio ; gardé en mémoire seulement (200 messages).
struct BrotherConsoleView: View {
    @ObservedObject var brother: BrotherPrinterService

    var body: some View {
        List {
            ForEach(brother.events.reversed()) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tag(for: event))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint(for: event))
                            .frame(width: 34, alignment: .leading)
                        Text(event.date, style: .time)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    if event.fields.isEmpty && event.battery == nil {
                        Text(event.text)
                            .font(.caption2)
                            .foregroundStyle(event.isError ? .red : .secondary)
                            .textSelection(.enabled)
                    } else {
                        InfoCard(title: event.text, fields: event.fields, battery: event.battery)
                    }
                }
            }
        }
        .overlay {
            if brother.events.isEmpty {
                Text("Journal Brother vide : recherchez ou imprimez pour le remplir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle("Journal Brother")
        .toolbar {
            Button("Effacer", role: .destructive) { brother.clearLog() }
                .disabled(brother.events.isEmpty)
        }
    }

    /// SCAN recherche, LINK connexion, PRT impression, INFO infos, ERR erreur.
    private func tag(for event: BrotherPrinterService.Event) -> String {
        if event.isError { return "ERR" }
        switch event.kind {
        case .search: return "SCAN"
        case .connection: return "LINK"
        case .print: return "PRT"
        case .info: return "INFO"
        case .general: return "SDK"
        }
    }

    private func tint(for event: BrotherPrinterService.Event) -> Color {
        if event.isError { return .red }
        switch event.kind {
        case .search: return .purple
        case .connection: return .orange
        case .print: return .blue
        case .info: return .teal
        case .general: return .secondary
        }
    }
}

/// Infos de l'imprimante : une ligne par valeur, jauge pour la batterie.
private struct InfoCard: View {
    let title: String
    let fields: [BrotherField]
    let battery: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            if let battery {
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon(battery))
                        .foregroundStyle(batteryColor(battery))
                        .frame(width: 18)
                    Text("Batterie").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(min(100, max(0, battery))), total: 100)
                        .tint(batteryColor(battery))
                    Text("\(battery) %").font(.caption.monospacedDigit())
                }
            }
            ForEach(fields, id: \.self) { field in
                HStack(spacing: 8) {
                    Image(systemName: field.icon).foregroundStyle(.teal).frame(width: 18)
                    Text(field.label).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(field.value)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(10)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        level < 20 ? .red : (level < 40 ? .orange : .green)
    }
}
