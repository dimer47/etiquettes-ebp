import SwiftUI

/// Lot de produits à imprimer en multi-impression : une entrée par produit (jamais de
/// doublon), chacune avec sa quantité propre. Scanner/sélectionner un produit déjà
/// présent n'ajoute pas de carte — ça incrémente sa quantité (+1).
@MainActor
final class BatchStore: ObservableObject {
    /// Une ligne du lot : le produit et la quantité d'étiquettes voulue.
    struct Entry: Identifiable, Equatable {
        let product: MappedProduct
        var quantity: Int
        /// Ajouté au lot replié ou déplié dans le récap.
        var expanded: Bool = false
        var id: String { product.id }
    }

    /// Quantité par défaut appliquée à CHAQUE nouveau produit ajouté au lot.
    /// Modifier la valeur par défaut n'écrase pas les quantités déjà ajustées à la main.
    @Published var defaultQuantity = 1
    @Published private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
    /// Nombre total d'étiquettes (somme des quantités).
    var totalLabels: Int { entries.reduce(0) { $0 + $1.quantity } }

    /// Un produit est-il déjà dans le lot ?
    func contains(_ product: MappedProduct) -> Bool {
        entries.contains { $0.id == product.id }
    }

    /// Ajoute un produit. S'il est déjà présent : +1 sur sa quantité (dédoublonnage).
    /// Sinon : nouvelle entrée à la quantité par défaut du lot.
    /// Renvoie `true` si c'était un doublon (incrément), `false` si nouvelle carte.
    @discardableResult
    func add(_ product: MappedProduct) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == product.id }) {
            entries[index].quantity = min(99, entries[index].quantity + 1)
            return true
        }
        entries.append(Entry(product: product, quantity: max(1, defaultQuantity)))
        return false
    }

    /// Bascule la présence d'un produit (pour les cases à cocher de la liste).
    func toggle(_ product: MappedProduct) {
        if contains(product) { remove(product) } else { add(product) }
    }

    func remove(_ product: MappedProduct) {
        entries.removeAll { $0.id == product.id }
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    func setQuantity(_ quantity: Int, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].quantity = min(99, max(1, quantity))
    }

    func increment(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].quantity = min(99, entries[index].quantity + 1)
    }

    func decrement(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].quantity = max(1, entries[index].quantity - 1)
    }

    func toggleExpanded(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].expanded.toggle()
    }

    /// Applique la quantité par défaut à TOUTES les entrées (remet le lot à plat).
    func applyDefaultToAll() {
        for index in entries.indices { entries[index].quantity = max(1, defaultQuantity) }
    }

    func clear() {
        entries.removeAll()
    }

    /// Construit les travaux pour la machine à états, dans l'ordre du lot.
    func makeJobs() -> [PrintQueueJob] {
        entries.map { PrintQueueJob(id: $0.id, quantity: $0.quantity) }
    }

    /// Retrouve le produit par son identifiant (pour que l'orchestrateur rende la
    /// bonne étiquette à partir d'une unité de la file).
    func product(id: String) -> MappedProduct? {
        entries.first(where: { $0.id == id })?.product
    }
}
