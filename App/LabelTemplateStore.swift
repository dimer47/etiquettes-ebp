import SwiftUI

/// Bibliothèque de modèles observable par l'UI : presets d'usine (verrouillés) + modèles
/// perso persistés en JSON dans UserDefaults. Enveloppe la logique pure `LabelTemplateLibrary`.
@MainActor
final class LabelTemplateLibraryStore: ObservableObject {
    static let storageKey = "labelTemplates"

    @Published private(set) var library: LabelTemplateLibrary

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            library = LabelTemplateLibrary(custom: LabelTemplateStore.decode(data))
        } else {
            library = LabelTemplateLibrary()
        }
    }

    /// Tous les modèles affichables (presets + perso).
    var all: [LabelTemplate] { library.all }
    var custom: [LabelTemplate] { library.custom }

    func template(id: UUID) -> LabelTemplate? { library.template(id: id) }
    func templateOrDefault(id: UUID?) -> LabelTemplate { library.templateOrDefault(id: id) }

    /// Duplique un modèle (preset ou perso) en modèle perso éditable ; retourne la copie.
    @discardableResult
    func duplicate(id: UUID) -> LabelTemplate? {
        let newId = library.duplicate(id: id)
        persist()
        return newId.flatMap { library.template(id: $0) }
    }

    /// Crée un modèle perso vierge nommé ; retourne-le.
    @discardableResult
    func createBlank(named name: String) -> LabelTemplate {
        let template = LabelTemplateLibrary.blankTemplate(named: name)
        library.add(template)
        persist()
        return template
    }

    /// Enregistre l'édition d'un modèle perso.
    func save(_ template: LabelTemplate) {
        library.update(template)
        persist()
    }

    /// Supprime un modèle perso.
    func delete(id: UUID) {
        library.delete(id: id)
        persist()
    }

    /// Purge tous les modèles perso (déconnexion gateway).
    func clear() {
        library = LabelTemplateLibrary()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        if let data = LabelTemplateStore.encode(library.custom) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
