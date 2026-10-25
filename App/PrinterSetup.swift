import Foundation

/// Imprimante choisie et réglages qui en dépendent, conservés dans
/// `UserDefaults` comme les autres préférences de l'app.
///
/// L'ordre compte : la famille et le modèle d'abord, le papier en découle.
/// Changer de modèle remet un papier compatible si l'ancien ne l'est plus
/// (un rouleau de 102 mm n'entre pas dans une TD-2), et retire les coupes
/// que la nouvelle série ne sait pas faire.
@MainActor
final class PrinterSetup: ObservableObject {
    @Published var brand: PrinterBrand {
        didSet { defaults.set(brand.rawValue, forKey: Key.brand) }
    }

    @Published var brotherModel: BrotherModel {
        didSet {
            defaults.set(brotherModel.rawValue, forKey: Key.model)
            ensureCompatibleMedia()
            let restricted = cut.restricted(to: brotherModel.series.cutter)
            if restricted != cut { cut = restricted }
        }
    }

    @Published var brotherMedia: BrotherMedia {
        didSet { store(brotherMedia, forKey: Key.media) }
    }

    /// Coupe désactivée par défaut : sur une TD le massicot est un accessoire.
    @Published var cut: BrotherCutOptions {
        didSet { store(cut, forKey: Key.cut) }
    }

    /// Densité, qualité, tramage, décolleur et marge (TD Print Studio).
    @Published var quality: BrotherQualityOptions {
        didSet { store(quality, forKey: Key.quality) }
    }

    @Published var copies: Int {
        didSet { defaults.set(copies, forKey: Key.copies) }
    }

    /// Liste du SDK des étiquettes QL / rubans PT acceptés par un modèle.
    var supportedLabels: (BrotherModel) -> Set<Int>? = { _ in nil } {
        didSet { ensureCompatibleMedia() }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let brand = "printer.brand"
        static let model = "printer.brother.model"
        static let media = "printer.brother.media"
        static let cut = "printer.brother.cut"
        static let copies = "printer.brother.copies"
        static let quality = "printer.brother.quality"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brand = defaults.string(forKey: Key.brand).flatMap(PrinterBrand.init) ?? .pocket5890
        let model = defaults.string(forKey: Key.model).flatMap(BrotherModel.init) ?? .defaultModel
        brotherModel = model
        let media: BrotherMedia? = Self.decode(defaults.data(forKey: Key.media))
        brotherMedia = media.flatMap { $0.isCompatible(with: model) ? $0 : nil } ?? .defaultMedia(for: model)
        cut = (Self.decode(defaults.data(forKey: Key.cut)) ?? BrotherCutOptions()).restricted(to: model.series.cutter)
        quality = Self.decode(defaults.data(forKey: Key.quality)) ?? BrotherQualityOptions()
        copies = min(99, max(1, defaults.object(forKey: Key.copies) as? Int ?? 1))
    }

    var brotherJob: BrotherJob {
        BrotherJob(model: brotherModel, media: brotherMedia,
                   cut: cut.restricted(to: brotherModel.series.cutter), quality: quality, copies: copies)
    }

    private func ensureCompatibleMedia() {
        let supported = supportedLabels(brotherModel)
        if !brotherMedia.isCompatible(with: brotherModel, supported: supported) {
            brotherMedia = .defaultMedia(for: brotherModel, supported: supported)
        }
    }

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
