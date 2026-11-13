import Foundation

/// Logique PURE de la bibliothèque de modèles : presets d'usine (verrouillés) + modèles
/// perso (persistés). Sans dépendance UIKit/SwiftUI, donc testable. La couche App l'enveloppe
/// dans un `ObservableObject` qui charge/sauvegarde les modèles perso en JSON.
public struct LabelTemplateLibrary: Equatable {
    /// Modèles perso (éditables), dans l'ordre de création.
    public private(set) var custom: [LabelTemplate]

    public init(custom: [LabelTemplate] = []) {
        self.custom = custom.filter { !$0.isLocked }
    }

    /// Presets d'usine (toujours en tête) suivis des modèles perso.
    public var all: [LabelTemplate] { LabelTemplatePresets.all + custom }

    /// Retrouve un modèle par id (preset ou perso).
    public func template(id: UUID) -> LabelTemplate? {
        all.first { $0.id == id }
    }

    /// Le modèle à utiliser pour un id, avec repli sur le preset par défaut si l'id est
    /// inconnu (modèle perso supprimé entre deux sessions, par exemple).
    public func templateOrDefault(id: UUID?) -> LabelTemplate {
        if let id, let found = template(id: id) { return found }
        return LabelTemplatePresets.default
    }

    // MARK: - Mutations (modèles perso uniquement)

    /// Ajoute un modèle perso et retourne son id.
    @discardableResult
    public mutating func add(_ template: LabelTemplate) -> UUID {
        var template = template
        template.isLocked = false
        custom.append(template)
        return template.id
    }

    /// Duplique n'importe quel modèle (preset ou perso) en un nouveau modèle perso éditable.
    /// Retourne l'id de la copie.
    @discardableResult
    public mutating func duplicate(id: UUID) -> UUID? {
        guard let source = template(id: id) else { return nil }
        let copy = source.duplicated(named: Self.copyName(of: source.name, existing: all.map(\.name)))
        custom.append(copy)
        return copy.id
    }

    /// Remplace un modèle perso existant (l'édition). Sans effet sur un preset verrouillé
    /// ou un id inconnu.
    public mutating func update(_ template: LabelTemplate) {
        guard !template.isLocked, let index = custom.firstIndex(where: { $0.id == template.id }) else { return }
        var template = template
        template.isLocked = false
        custom[index] = template
    }

    /// Supprime un modèle perso. Un preset verrouillé n'est jamais supprimé.
    public mutating func delete(id: UUID) {
        custom.removeAll { $0.id == id && !$0.isLocked }
    }

    /// Importe un modèle REÇU (partage QR/fichier) comme NOUVEAU modèle perso éditable.
    ///
    /// Dédoublonnage par NOM, simple et sûr : si un modèle du même nom existe déjà (parmi les
    /// presets ou les perso), l'importé est RENOMMÉ « Nom (importé) », « Nom (importé 2) »… — on
    /// n'écrase jamais un modèle existant, et on ne fusionne pas par id (deux appareils peuvent
    /// porter le même id pour des contenus différents). L'importé reçoit un NOUVEL id et n'est
    /// jamais verrouillé. Retourne l'id du modèle ajouté.
    @discardableResult
    public mutating func importTemplate(_ template: LabelTemplate) -> UUID {
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? NSLocalizedString("Modèle", comment: "Default template name") : name
        let finalName = all.map(\.name).contains(base)
            ? Self.importedName(of: base, existing: all.map(\.name))
            : base
        let imported = LabelTemplate(id: UUID(), name: finalName, isLocked: false,
                                     baseArrangement: nil, lines: template.materializedLines())
        custom.append(imported)
        return imported.id
    }

    /// Importe plusieurs modèles d'un coup ; retourne les ids ajoutés, dans l'ordre. Chaque import
    /// voit les précédents (deux modèles reçus du même nom se dédoublonnent entre eux).
    @discardableResult
    public mutating func importTemplates(_ templates: [LabelTemplate]) -> [UUID] {
        templates.map { importTemplate($0) }
    }

    /// Nom d'import unique : « Nom (importé) », « Nom (importé 2) », …
    static func importedName(of base: String, existing: [String]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? NSLocalizedString("Modèle", comment: "Default template name") : trimmed
        let first = String(format: NSLocalizedString("%@ (importé)", comment: "Imported template name"), root)
        if !existing.contains(first) { return first }
        var n = 2
        while true {
            let candidate = String(format: NSLocalizedString("%@ (importé %d)", comment: "Imported template name n"), root, n)
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Crée un modèle perso vierge nommé, à partir des lignes de la disposition « rayon actuel ».
    public static func blankTemplate(named name: String) -> LabelTemplate {
        LabelTemplate(name: name, isLocked: false,
                      lines: TemplateLine.referenceLines(for: .current))
    }

    /// Nom de copie unique : « Nom (copie) », « Nom (copie 2) », …
    static func copyName(of base: String, existing: [String]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? NSLocalizedString("Modèle", comment: "Default template name") : trimmed
        let first = String(format: NSLocalizedString("%@ (copie)", comment: "Duplicated template name"), root)
        if !existing.contains(first) { return first }
        var n = 2
        while true {
            let candidate = String(format: NSLocalizedString("%@ (copie %d)", comment: "Duplicated template name n"), root, n)
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }
}

/// Encodage/décodage JSON des modèles perso (persistance).
public enum LabelTemplateStore {
    public static func encode(_ custom: [LabelTemplate]) -> Data? {
        try? JSONEncoder().encode(custom.filter { !$0.isLocked })
    }
    public static func decode(_ data: Data) -> [LabelTemplate] {
        guard let decoded = try? JSONDecoder().decode([LabelTemplate].self, from: data) else { return [] }
        return decoded.filter { !$0.isLocked }
    }
}
