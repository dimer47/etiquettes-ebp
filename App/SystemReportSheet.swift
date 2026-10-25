import SwiftUI
import UIKit

/// Rapport système Brother en rubriques : résumé, erreurs, puis tout le
/// détail. Repris de TD Print Studio.
struct SystemReportSheet: View {
    let report: SystemReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Résumé") {
                    ForEach(summary, id: \.label) { row in
                        SummaryRow(icon: row.icon, label: row.label, value: row.value)
                    }
                }

                Section("Erreurs enregistrées") {
                    if report.recordedErrors.isEmpty {
                        Text("Aucune erreur enregistrée.").foregroundStyle(.secondary)
                    }
                    ForEach(report.recordedErrors, id: \.self) { entry in
                        SummaryRow(icon: "exclamationmark.triangle", label: errorLabel(entry.key),
                                   value: entry.value, tint: .red)
                    }
                }

                Section("Détail complet") {
                    ForEach(report.nonEmptySections, id: \.self) { section in
                        DisclosureGroup {
                            ForEach(report.entries(section), id: \.self) { entry in
                                EntryRow(entry: entry)
                            }
                        } label: {
                            HStack {
                                Text(title(for: section))
                                Spacer()
                                Text("\(report.entries(section).count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rapport système")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copier") { UIPasteboard.general.string = report.raw }
                }
            }
        }
    }

    private struct Row {
        let icon: String
        let label: String
        let value: String
    }

    /// Les informations utiles au quotidien, mises en forme.
    private var summary: [Row] {
        var rows: [Row] = []
        func add(_ icon: String, _ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            rows.append(Row(icon: icon, label: label, value: value))
        }
        add("printer", NSLocalizedString("Modèle", comment: "Report"), report.value("general_info_modelname"))
        add("number", NSLocalizedString("N° de série", comment: "Brother info"), report.value("general_info_serialnumber"))
        add("cpu", NSLocalizedString("Firmware", comment: "Brother info"), report.value("general_info_program_version"))
        add("doc.plaintext", NSLocalizedString("Papier chargé", comment: "Report"), paper)
        add("circle.lefthalf.filled", NSLocalizedString("Densité de l’imprimante", comment: "Report"), report.value("setting_print_density"))
        add("speedometer", NSLocalizedString("Vitesse", comment: "Report"), speed)
        add("scissors", NSLocalizedString("Massicot", comment: "Report"), report.value("option_cutter_status").map(translated))
        add("square.stack.3d.up", NSLocalizedString("Décolleur", comment: "Report"), report.value("option_peeler_status").map(translated))
        add("moon.zzz", NSLocalizedString("Mise en veille", comment: "Report"), minutes(report.value("setting_auto_sleep")))
        add("power", NSLocalizedString("Extinction auto", comment: "Report"), minutes(report.value("setting_auto_poweroff")))
        add("doc.on.doc", NSLocalizedString("Pages imprimées", comment: "Report"), report.value("print_total_page_count"))
        add("ruler", NSLocalizedString("Longueur imprimée", comment: "Report"), report.value("print_total_distance[m]").map { "\($0) m" })
        add("tray.full", NSLocalizedString("Travaux d’impression", comment: "Report"), report.value("print_job_count_total"))
        add("thermometer", NSLocalizedString("Température", comment: "Report"), report.value("environment_tempature_current").map { "\($0) °C" })
        return rows
    }

    /// Largeur en mm, longueur en mm, type de papier.
    private var paper: String? {
        guard let width = report.value("media_current_tape_width") else { return nil }
        var text = width
        if let length = report.value("media_current_tape_length"), length != "0" { text += " × \(length)" }
        text += " mm"
        if let kind = report.value("media_current_tape_kind") { text += " · " + translated(kind) }
        return text
    }

    /// « 6ips / 152.4mm/s » devient « 152,4 mm/s ».
    private var speed: String? {
        guard let value = report.value("setting_print_speed") else { return nil }
        guard let part = value.split(separator: "/").dropFirst().first?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "mm/s", with: "") else { return value }
        let number = Double(part).map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? part
        return "\(number) mm/s"
    }

    /// Valeurs courantes du firmware, en anglais, traduites quand on les connaît.
    private func translated(_ value: String) -> String {
        switch value.lowercased() {
        case "not connected": return NSLocalizedString("Non connecté", comment: "Report value")
        case "connected": return NSLocalizedString("Connecté", comment: "Report value")
        case "die-cut": return NSLocalizedString("Prédécoupé", comment: "Paper kind")
        case "continuous": return NSLocalizedString("Continu", comment: "Paper kind")
        case "black mark": return NSLocalizedString("Marque noire", comment: "Paper kind")
        default: return value
        }
    }

    private func title(for section: SystemReport.Section) -> String {
        switch section {
        case .identity: return NSLocalizedString("Identité", comment: "Report section")
        case .media: return NSLocalizedString("Papier chargé", comment: "Report")
        case .options: return NSLocalizedString("Accessoires", comment: "Report section")
        case .settings: return NSLocalizedString("Réglages", comment: "Report section")
        case .counters: return NSLocalizedString("Compteurs", comment: "Report section")
        case .errors: return NSLocalizedString("Erreurs", comment: "Report section")
        case .environment: return NSLocalizedString("Températures", comment: "Report section")
        case .communication: return NSLocalizedString("Liaison série", comment: "Report section")
        case .other: return NSLocalizedString("Autres", comment: "Report section")
        }
    }

    /// « error_history_01 » devient « Historique 1 », « error_count_3 » « Erreurs de type 3 ».
    private func errorLabel(_ key: String) -> String {
        if let number = Int(key.replacingOccurrences(of: "error_history_", with: "")) {
            return String(format: NSLocalizedString("Historique %d", comment: "Report error"), number)
        }
        if let number = Int(key.replacingOccurrences(of: "error_count_", with: "")) {
            return String(format: NSLocalizedString("Erreurs de type %d", comment: "Report error"), number)
        }
        return key
    }

    private func minutes(_ value: String?) -> String? {
        guard let value else { return nil }
        return value == "0" ? NSLocalizedString("Désactivée", comment: "Report") : "\(value) min"
    }
}

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .teal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct EntryRow: View {
    let entry: SystemReport.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.key).font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text(entry.value.isEmpty ? "—" : entry.value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}
