import Foundation

/// Historique des articles consultés (fiche ouverte depuis la liste), persistant.
/// Le plus récent en tête ; dédoublonné par référence produit (une même réf remonte).
@MainActor
final class ViewedProductStore: ObservableObject {
    @Published private(set) var entries: [ViewedProduct]
    private let defaults: UserDefaults
    static let storageKey = "viewedProductHistory"
    private static let maximumEntries = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([ViewedProduct].self, from: $0) } ?? []
    }

    /// Enregistre une consultation ; si la même référence existe déjà, on la remonte en tête.
    func record(_ label: ProductLabel) {
        let ref = label.productReference.trimmingCharacters(in: .whitespaces)
        entries.removeAll { !ref.isEmpty && $0.label.productReference.trimmingCharacters(in: .whitespaces) == ref }
        entries.insert(ViewedProduct(label: label), at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { entries.remove(at: index) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
