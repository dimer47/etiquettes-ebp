import Foundation

/// Rapport systeme d'une imprimante Brother, range par rubriques.
///
/// Le SDK renvoie un texte `cle=valeur`, une ligne par entree, dans l'ordre
/// du firmware. Les rubriques sont deduites du prefixe de la cle.
public struct SystemReport: Equatable, Sendable {
    public enum Section: String, CaseIterable, Sendable {
        case identity
        case media
        case options
        case settings
        case counters
        case errors
        case environment
        case communication
        case other
    }

    public struct Entry: Equatable, Hashable, Sendable {
        public let key: String
        public let value: String
    }

    /// Entrees par rubrique, dans l'ordre du rapport.
    public let sections: [Section: [Entry]]
    /// Texte d'origine, pour la copie.
    public let raw: String

    public init(parsing text: String) {
        var sections: [Section: [Entry]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equal = line.firstIndex(of: "=") else { continue }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            sections[Self.section(for: key), default: []].append(Entry(key: key, value: value))
        }
        self.sections = sections
        self.raw = text
    }

    public func entries(_ section: Section) -> [Entry] { sections[section] ?? [] }

    public func value(_ key: String) -> String? {
        for entries in sections.values {
            if let entry = entries.first(where: { $0.key == key }) { return entry.value }
        }
        return nil
    }

    /// Rubriques non vides, dans l'ordre d'affichage.
    public var nonEmptySections: [Section] {
        Section.allCases.filter { !(sections[$0] ?? []).isEmpty }
    }

    /// Erreurs reellement survenues: historique non vide, compteurs non nuls.
    public var recordedErrors: [Entry] {
        entries(.errors).filter { entry in
            if entry.key.hasPrefix("error_history_") { return entry.value != "00(0)" }
            if entry.key == "error_count_total" { return false }
            return entry.value != "0"
        }
    }

    static func section(for key: String) -> Section {
        let rules: [(String, Section)] = [
            ("general_info_", .identity),
            ("media_current_", .media),
            ("option_", .options),
            ("setting_", .settings),
            ("comm_", .communication),
            ("error_", .errors),
            ("environment_", .environment),
            ("head_tempature", .environment),
            ("print_", .counters),
            ("cutter_", .counters),
            ("feed_", .counters),
            ("head_", .counters),
            ("key_", .counters),
            ("cover_", .counters),
            ("power_", .counters),
            ("cooling_", .counters),
            ("media_info", .counters),
            ("peeler_", .counters)
        ]
        return rules.first { key.hasPrefix($0.0) }?.1 ?? .other
    }
}
