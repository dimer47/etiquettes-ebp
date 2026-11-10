import Foundation

/// Un article consulté (fiche ouverte depuis la liste), pour l'historique de consultation.
/// Distinct de `PrintedLabel` (qui porte les réglages d'impression) : ici on ne garde que
/// l'étiquette produit et la date de consultation.
public struct ViewedProduct: Codable, Equatable, Identifiable {
    public let id: UUID
    public let viewedAt: Date
    public let label: ProductLabel

    public init(id: UUID = UUID(), viewedAt: Date = Date(), label: ProductLabel) {
        self.id = id
        self.viewedAt = viewedAt
        self.label = label
    }
}
