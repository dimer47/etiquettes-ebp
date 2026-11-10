import Foundation

/// Construit le paramètre `WhereCondition` (filtre générique EBP) envoyé à la gateway
/// pour rechercher des articles. Fonction pure et isolée : si la syntaxe exacte du filtre
/// EBP diffère, c'est le seul endroit à corriger (et un seul test à ajuster).
///
/// Syntaxe utilisée (OData-like, telle que documentée côté EBP) :
///   contains(Caption,'<texte>') or contains(Id,'<texte>')
public enum GatewayWhereCondition {

    /// Condition de recherche libre sur le libellé (Caption) ou la référence (Id).
    /// Retourne nil pour une saisie vide.
    public static func search(_ text: String) -> String? {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        let safe = escape(term)
        return "contains(Caption,'\(safe)') or contains(Id,'\(safe)')"
    }

    /// Filtre d'égalité sur la famille.
    public static func family(_ familyId: String) -> String? {
        let id = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return "FamilyId eq '\(escape(id))'"
    }

    /// Compose plusieurs conditions avec « and », en ignorant les nils.
    /// Chaque sous-condition est parenthésée pour préserver la priorité.
    public static func and(_ parts: [String?]) -> String? {
        let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
        guard !present.isEmpty else { return nil }
        if present.count == 1 { return present[0] }
        return present.map { "(\($0))" }.joined(separator: " and ")
    }

    /// Échappe les apostrophes pour la syntaxe de filtre (doublage, convention OData).
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
