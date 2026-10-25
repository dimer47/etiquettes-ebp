import CoreGraphics
import Foundation
#if canImport(BRLMPrinterKit)
import BRLMPrinterKit
#endif

/// Imprimante Brother trouvée par une recherche, ou saisie à la main.
struct BrotherTarget: Codable, Hashable, Identifiable {
    let connection: BrotherConnection
    /// Nom local BLE annoncé, ou adresse IP en Wi-Fi.
    let address: String
    /// Nom renvoyé par le SDK, par exemple « Brother TD-4550DNWB ». Vide pour
    /// une adresse saisie à la main.
    let modelName: String

    var id: String { connection.rawValue + "|" + address }
    var displayName: String { modelName.isEmpty ? address : modelName }
    var advertisedModel: BrotherModel? { BrotherModel.matching(advertisedName: modelName) }
}

/// Ce qu'il faut savoir pour imprimer sur une Brother.
struct BrotherJob {
    let model: BrotherModel
    let media: BrotherMedia
    let cut: BrotherCutOptions
    let copies: Int
}

/// Communication avec les imprimantes Brother via le Brother Print SDK.
///
/// Le SDK est bloquant (recherche, ouverture du canal, impression) : tout
/// passe par une file dédiée, seul le résultat revient sur le fil principal.
/// Sans le SDK, l'application compile et affiche « SDK absent ».
@MainActor
final class BrotherPrinterService: ObservableObject {
    enum Activity: Equatable { case idle, searching, connecting, printing }

    static let isSDKAvailable: Bool = {
        #if canImport(BRLMPrinterKit)
        return true
        #else
        return false
        #endif
    }()

    @Published private(set) var activity: Activity = .idle
    @Published private(set) var found: [BrotherTarget] = []
    @Published private(set) var status: String
    @Published private(set) var statusIsError = false
    /// Modèle annoncé par l'imprimante lors du dernier test de connexion.
    @Published private(set) var reportedModel: BrotherModel?
    @Published var target: BrotherTarget? {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(target), forKey: Self.targetKey)
            if oldValue != target { reportedModel = nil }
        }
    }

    private static let targetKey = "brother.target"
    private let queue = DispatchQueue(label: "ProductLabel5890.brother", qos: .userInitiated)
    private var searchCanceled = false

    init() {
        status = Self.isSDKAvailable
            ? NSLocalizedString("Aucune imprimante Brother choisie", comment: "Brother status")
            : NSLocalizedString("Brother Print SDK absent", comment: "Brother status")
        statusIsError = !Self.isSDKAvailable
        if let data = UserDefaults.standard.data(forKey: Self.targetKey) {
            target = try? JSONDecoder().decode(BrotherTarget.self, from: data)
        }
        if let target, Self.isSDKAvailable {
            status = String(format: NSLocalizedString("Imprimante choisie : %@", comment: "Brother status"), target.displayName)
        }
    }

    var isBusy: Bool { activity != .idle }
    var canPrint: Bool { Self.isSDKAvailable && target != nil && activity == .idle }

    /// Modèle signalé par l'imprimante : état lu, sinon nom de la recherche.
    var detectedModel: BrotherModel? { reportedModel ?? target?.advertisedModel }

    // MARK: - Recherche

    func search(_ connection: BrotherConnection, duration: TimeInterval = 10) {
        guard activity == .idle else { return }
        guard Self.isSDKAvailable else { return report(NSLocalizedString("Brother Print SDK absent", comment: "Brother status"), isError: true) }
        found.removeAll()
        searchCanceled = false
        activity = .searching
        report(String(format: NSLocalizedString("Recherche %@ pendant %d s…", comment: "Brother search"),
                      connection.title, Int(duration)))
        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let onFound: (BRLMChannel) -> Void = { channel in
                let modelName = channel.extraInfo?.value(forKey: BRLMChannelExtraInfoKeyModelName) as? String ?? ""
                let printer = BrotherTarget(connection: connection, address: channel.channelInfo, modelName: modelName)
                Task { @MainActor in self?.add(printer) }
            }
            let result: BRLMPrinterSearchResult
            switch connection {
            case .ble:
                let option = BRLMBLESearchOption()
                option.searchDuration = duration
                result = BRLMPrinterSearcher.startBLESearch(option, callback: onFound)
            case .wifi, .bluetoothClassic:
                let option = BRLMNetworkSearchOption()
                option.searchDuration = duration
                result = BRLMPrinterSearcher.startNetworkSearch(option, callback: onFound)
            }
            let message = BrotherSDKBridge.searchMessage(result.error.code)
            Task { @MainActor in self?.finishSearch(errorMessage: message) }
        }
        #endif
    }

    func cancelSearch() {
        guard activity == .searching else { return }
        searchCanceled = true
        #if canImport(BRLMPrinterKit)
        // Pas sur `queue` : la recherche en cours l'occupe jusqu'à la fin.
        DispatchQueue.global(qos: .userInitiated).async {
            BRLMPrinterSearcher.cancelBLESearch()
            BRLMPrinterSearcher.cancelNetworkSearch()
        }
        #endif
    }

    /// Wi-Fi : adresse IP connue, sans recherche.
    func useAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        select(BrotherTarget(connection: .wifi, address: trimmed, modelName: ""))
    }

    func select(_ printer: BrotherTarget) {
        target = printer
        report(String(format: NSLocalizedString("Imprimante choisie : %@", comment: "Brother status"), printer.displayName))
    }

    func forget() {
        target = nil
        report(NSLocalizedString("Aucune imprimante Brother choisie", comment: "Brother status"))
    }

    private func add(_ printer: BrotherTarget) {
        guard !found.contains(where: { $0.id == printer.id }) else { return }
        found.append(printer)
    }

    private func finishSearch(errorMessage: String?) {
        activity = .idle
        if let errorMessage { report(errorMessage, isError: true) }
        else if searchCanceled { report(String(format: NSLocalizedString("Recherche arrêtée. %d imprimante(s) trouvée(s)", comment: "Brother search"), found.count)) }
        else if found.isEmpty { report(NSLocalizedString("Aucune imprimante Brother trouvée. Vérifiez qu’elle est allumée, que son Bluetooth ou son Wi-Fi est actif et qu’elle n’est pas connectée à un autre appareil.", comment: "Brother search"), isError: true) }
        else { report(String(format: NSLocalizedString("%d imprimante(s) trouvée(s)", comment: "Brother search"), found.count)) }
    }

    // MARK: - État

    /// Ouvre le canal, lit l'état, referme. Teste la connexion sans imprimer.
    func checkStatus(selectedModel: BrotherModel) {
        guard activity == .idle else { return }
        guard Self.isSDKAvailable else { return report(NSLocalizedString("Brother Print SDK absent", comment: "Brother status"), isError: true) }
        guard let target else { return report(NSLocalizedString("Choisissez d’abord une imprimante Brother.", comment: "Brother status"), isError: true) }
        activity = .connecting
        report(String(format: NSLocalizedString("Connexion à %@…", comment: "Printer status"), target.displayName))
        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let outcome = BrotherSDKBridge.readStatus(target: target)
            Task { @MainActor in
                guard let self else { return }
                self.activity = .idle
                if let model = outcome.reportedModel { self.reportedModel = model }
                var message = outcome.message
                if let detected = outcome.reportedModel, detected != selectedModel {
                    message += "\n" + String(format: NSLocalizedString("L’imprimante annonce %@ alors que %@ est choisi.", comment: "Brother model mismatch"),
                                             detected.title, selectedModel.title)
                }
                self.report(message, isError: outcome.isError)
            }
        }
        #endif
    }

    // MARK: - Impression

    /// Dessine puis imprime, hors du fil principal. `render` reçoit l'échelle
    /// qui amène l'étiquette à la résolution de la tête. `onSuccess` n'est
    /// appelé que si le SDK a accepté le travail.
    func print(job: BrotherJob, layoutHeight: Int,
               render: @escaping @Sendable (_ scale: Double) throws -> CGImage,
               onSuccess: (() -> Void)? = nil) {
        guard activity == .idle else { return }
        guard Self.isSDKAvailable else { return report(NSLocalizedString("Brother Print SDK absent", comment: "Brother status"), isError: true) }
        guard let target else { return report(NSLocalizedString("Choisissez d’abord une imprimante Brother.", comment: "Brother status"), isError: true) }
        activity = .printing
        report(String(format: NSLocalizedString("Impression sur %@…", comment: "Brother status"), job.model.title))
        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let outcome: BrotherSDKBridge.Outcome
            do {
                let dpi = BrotherSDKBridge.dpi(for: job.model)
                let area = job.media.printableAreaMM(for: job.model)
                let scale = LabelRasterGeometry.scale(layoutHeight: layoutHeight, area: area, dpi: dpi)
                outcome = BrotherSDKBridge.print(image: try render(scale), job: job, target: target)
            } catch {
                outcome = .init(message: String(format: NSLocalizedString("Rendu impossible : %@", comment: "Render error"),
                                                error.localizedDescription), isError: true)
            }
            Task { @MainActor in
                guard let self else { return }
                self.activity = .idle
                self.report(outcome.message, isError: outcome.isError)
                if !outcome.isError { onSuccess?() }
            }
        }
        #endif
    }

    /// Étiquettes QL ou rubans PT acceptés par le modèle selon le SDK
    /// (`supportedQLLabels`, `supportedPTLabels`). Nil sans SDK.
    nonisolated static func supportedLabelIndices(for model: BrotherModel) -> Set<Int>? {
        #if canImport(BRLMPrinterKit)
        let spec = BRLMPrinterModelSpec(printerModel: BrotherSDKBridge.sdkModel(model))
        let numbers: [NSNumber]
        switch model.series.paperSource {
        case .qlLabel: numbers = spec.supportedQLLabels
        case .ptTape: numbers = spec.supportedPTLabels
        default: return nil
        }
        let indices = Set(numbers.map(\.intValue))
        return indices.isEmpty ? nil : indices
        #else
        return nil
        #endif
    }

    nonisolated static func supportedLabels(for model: BrotherModel) -> [BrotherLabelSize] {
        let list = model.series == .ql ? BrotherLabelSize.ql : model.series == .pt ? BrotherLabelSize.pt : []
        guard let indices = Self.supportedLabelIndices(for: model) else { return list }
        return list.filter { indices.contains($0.index) }
    }

    func reportError(_ text: String) { report(text, isError: true) }

    private func report(_ text: String, isError: Bool = false) {
        status = text
        statusIsError = isError
    }
}

#if canImport(BRLMPrinterKit)
/// Traduction entre l'application et le Brother Print SDK. Noms vérifiés dans
/// les en-têtes de BRLMPrinterKit.xcframework (SDK 4.13).
enum BrotherSDKBridge {
    struct Outcome {
        var message: String
        var isError: Bool
        var reportedModel: BrotherModel? = nil
    }

    static func dpi(for model: BrotherModel) -> Double {
        let spec = BRLMPrinterModelSpec(printerModel: sdkModel(model))
        return spec.xdpi > 0 ? spec.xdpi : 203
    }

    // MARK: Canal

    static func channel(for target: BrotherTarget) -> BRLMChannel? {
        switch target.connection {
        case .ble: return BRLMChannel(bleLocalName: target.address)
        case .wifi: return BRLMChannel(wifiIPAddress: target.address)
        case .bluetoothClassic: return nil
        }
    }

    /// Ouvre le canal, exécute `body`, referme toujours le canal.
    private static func withDriver(target: BrotherTarget, _ body: (BRLMPrinterDriver) -> Outcome) -> Outcome {
        guard let channel = channel(for: target) else {
            return Outcome(message: NSLocalizedString("Bluetooth Classic (MFi) non géré par l’application.", comment: "Brother error"), isError: true)
        }
        let generated = BRLMPrinterDriverGenerator.open(channel)
        guard generated.error.code == .noError, let driver = generated.driver else {
            return Outcome(message: openChannelMessage(generated.error.code), isError: true)
        }
        defer { driver.closeChannel() }
        return body(driver)
    }

    // MARK: État

    static func readStatus(target: BrotherTarget) -> Outcome {
        withDriver(target: target) { driver in
            let result = driver.getPrinterStatus()
            guard result.error.code == .noError, let status = result.status else {
                return Outcome(message: NSLocalizedString("Connexion établie, mais état illisible.", comment: "Brother status"), isError: true)
            }
            let model = appModel(status.model)
            var parts = [statusMessage(status.errorCode)]
            if let model { parts.append(model.title) }
            if let battery = status.batteryStatus, battery.chargeLevel.max > 0 {
                parts.append(String(format: NSLocalizedString("Batterie %d/%d", comment: "Brother battery"),
                                    Int(battery.chargeLevel.current), Int(battery.chargeLevel.max)))
            }
            if let media = status.mediaInfo, media.width_mm > 0 {
                parts.append(String(format: NSLocalizedString("Papier %d mm", comment: "Brother media"), Int(media.width_mm)))
            }
            return Outcome(message: parts.joined(separator: " · "),
                           isError: status.errorCode != .noError, reportedModel: model)
        }
    }

    // MARK: Impression

    static func print(image: CGImage, job: BrotherJob, target: BrotherTarget) -> Outcome {
        guard let settings = settings(for: job) else {
            return Outcome(message: NSLocalizedString("Réglages refusés par le SDK pour ce modèle.", comment: "Brother error"), isError: true)
        }
        // Le SDK signale avant l'envoi un réglage incohérent avec le modèle.
        let report = BRLMValidatePrintSettings.validate(settings)
        let errors = report.issues.filter { $0.rank == .error }.map(\.message)
        if !errors.isEmpty {
            return Outcome(message: NSLocalizedString("Réglages invalides :", comment: "Brother validation") + "\n"
                           + errors.joined(separator: "\n"), isError: true)
        }
        let warnings = report.issues.filter { $0.rank == .warning }.map(\.message)
        var outcome = withDriver(target: target) { driver in
            let error = driver.printImage(with: image, settings: settings)
            if error.code == .noError {
                return Outcome(message: NSLocalizedString("Étiquette envoyée à l’imprimante.", comment: "Brother print"), isError: false)
            }
            return Outcome(message: printMessage(error.code, cutRequested: job.cut.isAnyCutRequested), isError: true)
        }
        if !warnings.isEmpty { outcome.message += "\n" + warnings.joined(separator: "\n") }
        return outcome
    }

    static func settings(for job: BrotherJob) -> BRLMPrintSettingsProtocol? {
        let model = sdkModel(job.model)
        let cut = job.cut.restricted(to: job.model.series.cutter)
        switch job.model.series {
        case .td:
            guard let settings = BRLMTDPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .custom(paper) = job.media { settings.customPaperSize = customPaperSize(paper) }
            // autoCut : après chaque page ou toutes les N pages ; cutAtEnd :
            // après la dernière. Sans massicot installé, rien n'est coupé.
            settings.autoCut = cut.autoCut
            settings.autoCutForEachPageCount = cut.clampedCutEveryPages
            settings.cutAtEnd = cut.cutAtEnd
            applyImageDefaults(settings, copies: job.copies)
            return settings
        case .rj:
            guard let settings = BRLMRJPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .custom(paper) = job.media { settings.customPaperSize = customPaperSize(paper) }
            applyImageDefaults(settings, copies: job.copies)
            return settings
        case .ql:
            guard let settings = BRLMQLPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .qlLabel(index) = job.media, let size = BRLMQLPrintSettingsLabelSize(rawValue: index) {
                settings.labelSize = size
            }
            settings.autoCut = cut.autoCut
            settings.autoCutForEachPageCount = cut.clampedCutEveryPages
            settings.cutAtEnd = cut.cutAtEnd
            applyImageDefaults(settings, copies: job.copies)
            return settings
        case .pt:
            guard let settings = BRLMPTPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .ptTape(index) = job.media, let size = BRLMPTPrintSettingsLabelSize(rawValue: index) {
                settings.labelSize = size
            }
            settings.autoCut = cut.autoCut
            applyImageDefaults(settings, copies: job.copies)
            return settings
        case .pj:
            guard let settings = BRLMPJPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .sheet(sheet) = job.media {
                settings.paperSize = BRLMPJPrintSettingsPaperSize(paperSizeStandard: paperSizeStandard(sheet))
            }
            applyImageDefaults(settings, copies: job.copies)
            return settings
        case .mw:
            // Le format (A6 ou A7) est imposé par le modèle : paperSize est en lecture seule.
            guard let settings = BRLMMWPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            applyImageDefaults(settings, copies: job.copies)
            return settings
        }
    }

    private static func applyImageDefaults(_ settings: BRLMPrintImageSettings, copies: Int) {
        settings.numCopies = UInt(max(1, copies))
        // Image mise à la taille de la page en gardant ses proportions.
        settings.scaleMode = .fitPageAspect
        settings.hAlignment = .center
        settings.vAlignment = .center
        // Seuil : traits nets, sans trame, pour le texte et le code-barres.
        settings.halftone = .threshold
    }

    private static func customPaperSize(_ paper: BrotherPaper) -> BRLMCustomPaperSize {
        let margin = CGFloat(paper.marginMM)
        let margins = BRLMCustomPaperSizeMargins(top: margin, left: margin, bottom: margin, right: margin)
        switch paper.kind {
        case .roll:
            return BRLMCustomPaperSize(rollWithTapeWidth: CGFloat(paper.widthMM),
                                       margins: margins, unitOfLength: .mm)
        case .dieCut:
            return BRLMCustomPaperSize(dieCutWithTapeWidth: CGFloat(paper.widthMM),
                                       tapeLength: CGFloat(paper.lengthMM), margins: margins,
                                       gapLength: CGFloat(paper.gapMM), unitOfLength: .mm)
        case .markRoll:
            return BRLMCustomPaperSize(markRollWithTapeWidth: CGFloat(paper.widthMM),
                                       tapeLength: CGFloat(paper.lengthMM), margins: margins,
                                       markPosition: CGFloat(paper.markOffsetMM),
                                       markHeight: CGFloat(paper.markLengthMM), unitOfLength: .mm)
        }
    }

    private static func paperSizeStandard(_ sheet: BrotherSheet) -> BRLMPJPrintSettingsPaperSizeStandard {
        switch sheet {
        case .a4: return .A4
        case .letter: return .letter
        case .legal: return .legal
        case .a5: return .A5
        }
    }

    // MARK: Modèles

    static func appModel(_ model: BRLMPrinterModel) -> BrotherModel? {
        BrotherModel.allCases.first { sdkModel($0) == model }
    }

    // Noms Swift importés : les cas sans minuscule gardent leur nom
    // (.TD_4550DNWB) ; les autres ont leur préfixe en minuscules (.pj_763MFi).
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func sdkModel(_ model: BrotherModel) -> BRLMPrinterModel {
        switch model {
        case .PJ_673: return .PJ_673
        case .PJ_763MFi: return .pj_763MFi
        case .PJ_773: return .PJ_773
        case .PJ_822: return .PJ_822
        case .PJ_823: return .PJ_823
        case .PJ_862: return .PJ_862
        case .PJ_863: return .PJ_863
        case .PJ_883: return .PJ_883
        case .MW_145MFi: return .mw_145MFi
        case .MW_260MFi: return .mw_260MFi
        case .MW_170: return .MW_170
        case .MW_270: return .MW_270
        case .RJ_2050: return .RJ_2050
        case .RJ_2140: return .RJ_2140
        case .RJ_2150: return .RJ_2150
        case .RJ_3050: return .RJ_3050
        case .RJ_3050Ai: return .rj_3050Ai
        case .RJ_3150: return .RJ_3150
        case .RJ_3150Ai: return .rj_3150Ai
        case .RJ_3230B: return .RJ_3230B
        case .RJ_3235B: return .RJ_3235B
        case .RJ_3250WB: return .RJ_3250WB
        case .RJ_3255WB: return .RJ_3255WB
        case .RJ_4030Ai: return .rj_4030Ai
        case .RJ_4040: return .RJ_4040
        case .RJ_4230B: return .RJ_4230B
        case .RJ_4235B: return .RJ_4235B
        case .RJ_4250WB: return .RJ_4250WB
        case .RJ_4255WB: return .RJ_4255WB
        case .TD_2030A: return .TD_2030A
        case .TD_2120N: return .TD_2120N
        case .TD_2125N: return .TD_2125N
        case .TD_2125NWB: return .TD_2125NWB
        case .TD_2130N: return .TD_2130N
        case .TD_2135N: return .TD_2135N
        case .TD_2135NWB: return .TD_2135NWB
        case .TD_2310D_203: return .TD_2310D_203
        case .TD_2310D_300: return .TD_2310D_300
        case .TD_2320D_203: return .TD_2320D_203
        case .TD_2320D_300: return .TD_2320D_300
        case .TD_2320DF_203: return .TD_2320DF_203
        case .TD_2320DF_300: return .TD_2320DF_300
        case .TD_2320DSA_203: return .TD_2320DSA_203
        case .TD_2320DSA_300: return .TD_2320DSA_300
        case .TD_2350D_203: return .TD_2350D_203
        case .TD_2350D_300: return .TD_2350D_300
        case .TD_2350DF_203: return .TD_2350DF_203
        case .TD_2350DF_300: return .TD_2350DF_300
        case .TD_2350DSA_203: return .TD_2350DSA_203
        case .TD_2350DSA_300: return .TD_2350DSA_300
        case .TD_2350DFSA_203: return .TD_2350DFSA_203
        case .TD_2350DFSA_300: return .TD_2350DFSA_300
        case .TD_4100N: return .TD_4100N
        case .TD_4415D: return .TD_4415D
        case .TD_4420DN: return .TD_4420DN
        case .TD_4425DN: return .TD_4425DN
        case .TD_4425DNF: return .TD_4425DNF
        case .TD_4455DNWB: return .TD_4455DNWB
        case .TD_4520DN: return .TD_4520DN
        case .TD_4525DN: return .TD_4525DN
        case .TD_4550DNWB: return .TD_4550DNWB
        case .TD_4555DNWB: return .TD_4555DNWB
        case .TD_4555DNWBF: return .TD_4555DNWBF
        case .QL_710W: return .QL_710W
        case .QL_720NW: return .QL_720NW
        case .QL_810W: return .QL_810W
        case .QL_820NWB: return .QL_820NWB
        case .QL_1110NWB: return .QL_1110NWB
        case .QL_1115NWB: return .QL_1115NWB
        case .PT_D410: return .PT_D410
        case .PT_D460BT: return .PT_D460BT
        case .PT_D610BT: return .PT_D610BT
        case .PT_D800W: return .PT_D800W
        case .PT_E310BT: return .PT_E310BT
        case .PT_E510: return .PT_E510
        case .PT_E550W: return .PT_E550W
        case .PT_E560BT: return .PT_E560BT
        case .PT_E720BT: return .PT_E720BT
        case .PT_E800W: return .PT_E800W
        case .PT_E850TKW: return .PT_E850TKW
        case .PT_E920BT: return .PT_E920BT
        case .PT_N25BT: return .PT_N25BT
        case .PT_P300BT: return .PT_P300BT
        case .PT_P300BTz: return .pt_P300BTz
        case .PT_P710BT: return .PT_P710BT
        case .PT_P715eBT: return .pt_P715eBT
        case .PT_P750W: return .PT_P750W
        case .PT_P900W: return .PT_P900W
        case .PT_P910BT: return .PT_P910BT
        case .PT_P950NW: return .PT_P950NW
        }
    }

    // MARK: Messages

    static func searchMessage(_ code: BRLMPrinterSearchErrorCode) -> String? {
        switch code {
        case .noError, .canceled: return nil
        case .alreadySearching: return NSLocalizedString("Une recherche est déjà en cours.", comment: "Brother search")
        case .unsupported: return NSLocalizedString("Recherche non prise en charge : vérifiez Bluetooth, le réseau local et les autorisations de l’app.", comment: "Brother search")
        default: return NSLocalizedString("La recherche a échoué.", comment: "Brother search")
        }
    }

    static func openChannelMessage(_ code: BRLMOpenChannelErrorCode) -> String {
        switch code {
        case .timeout: return NSLocalizedString("Délai dépassé : l’imprimante ne répond pas. Rapprochez l’iPhone et vérifiez qu’elle est allumée.", comment: "Brother open")
        default: return NSLocalizedString("Connexion impossible à l’imprimante.", comment: "Brother open")
        }
    }

    static func statusMessage(_ code: BRLMPrinterStatusErrorCode) -> String {
        switch code {
        case .noError: return NSLocalizedString("Prête", comment: "Brother status")
        case .noPaper: return NSLocalizedString("Plus de papier.", comment: "Brother error")
        case .coverOpen: return NSLocalizedString("Capot ouvert.", comment: "Brother error")
        case .busy: return NSLocalizedString("Imprimante occupée.", comment: "Brother error")
        case .paperJam: return NSLocalizedString("Bourrage papier.", comment: "Brother error")
        case .batteryEmpty, .batteryTrouble: return NSLocalizedString("Problème de batterie.", comment: "Brother error")
        case .incompatibleOptionalEquipment: return optionalEquipmentMessage
        default: return NSLocalizedString("Erreur de l’imprimante.", comment: "Brother error")
        }
    }

    static let optionalEquipmentMessage = NSLocalizedString(
        "Équipement optionnel incompatible ou absent. Si la coupe est activée, vérifiez que le massicot est installé, ou désactivez la coupe.",
        comment: "Brother error")

    // swiftlint:disable:next cyclomatic_complexity
    static func printMessage(_ code: BRLMPrintErrorCode, cutRequested: Bool) -> String {
        let text: String
        switch code {
        case .printerStatusErrorPaperEmpty: text = NSLocalizedString("Plus de papier.", comment: "Brother error")
        case .printerStatusErrorCoverOpen: text = NSLocalizedString("Capot ouvert.", comment: "Brother error")
        case .printerStatusErrorBusy: text = NSLocalizedString("Imprimante occupée.", comment: "Brother error")
        case .printerStatusErrorPaperJam, .printerStatusErrorMediaCannotBeFed:
            text = NSLocalizedString("Bourrage papier.", comment: "Brother error")
        case .printerStatusErrorBatteryWeak: text = NSLocalizedString("Problème de batterie.", comment: "Brother error")
        case .printerStatusErrorPrinterTurnedOff: text = NSLocalizedString("Imprimante éteinte.", comment: "Brother error")
        case .printerStatusErrorOverHeat: text = NSLocalizedString("Tête trop chaude : attendez avant de relancer.", comment: "Brother error")
        case .printerStatusErrorCommunicationError, .channelTimeout, .channelErrorStreamStatusError:
            text = NSLocalizedString("Communication interrompue avec l’imprimante.", comment: "Brother error")
        case .channelErrorUnsupportedChannel:
            text = NSLocalizedString("Ce mode de connexion n’est pas pris en charge par le framework installé.", comment: "Brother error")
        case .printerStatusErrorIncompatibleOptionalEquipment:
            text = cutRequested
                ? NSLocalizedString("La coupe est demandée mais le massicot n’est pas installé ou n’est pas reconnu. Désactivez la coupe ou installez le massicot.", comment: "Brother error")
                : optionalEquipmentMessage
        case .customPaperSizeError, .setLabelSizeError, .setMarginError, .setLengthError:
            text = NSLocalizedString("Papier refusé : vérifiez les dimensions et le type de papier.", comment: "Brother error")
        case .printSettingsError, .printSettingsNotSupportError:
            text = NSLocalizedString("Réglages refusés par le SDK pour ce modèle.", comment: "Brother error")
        case .printerModelError, .setModelError:
            text = NSLocalizedString("Le modèle choisi ne correspond pas à l’imprimante.", comment: "Brother error")
        case .canceled: text = NSLocalizedString("Impression annulée.", comment: "Brother error")
        default: text = NSLocalizedString("Erreur de l’imprimante.", comment: "Brother error")
        }
        return text + " (\(code.rawValue))"
    }
}
#endif
