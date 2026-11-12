import Foundation

/// Un travail de la file : un produit × une quantité. Chaque unité est une étiquette.
public struct PrintQueueJob: Equatable, Hashable, Identifiable {
    public let id: String
    public let quantity: Int

    public init(id: String, quantity: Int) {
        self.id = id
        self.quantity = max(1, quantity)
    }
}

/// Machine à états d'une impression séquentielle multi-produits, pensée pour la
/// pause/reprise sur erreur. Logique pure (aucun service d'impression, aucune UI) :
/// elle décide seulement QUELLE étiquette imprimer ensuite et comment réagir à un
/// succès ou à un échec. L'orchestrateur (côté App) pilote les imprimantes réelles
/// et lui transmet le résultat de chaque étiquette.
///
/// Déroulé : la file aplatit les travaux en une suite d'étiquettes (job 0 × q0,
/// job 1 × q1, …). Un curseur avance à chaque succès. Un échec met la file en
/// `paused(atUnit:)` SANS avancer le curseur : l'étiquette qui a échoué reste la
/// prochaine à sortir. L'utilisateur choisit alors `retry` (réessayer la même),
/// `skipFailed` (sauter celle-ci et continuer) ou `cancel` (tout arrêter).
public struct PrintQueueMachine: Equatable {
    public enum State: Equatable {
        /// En attente d'un `start()`.
        case idle
        /// Impression de l'unité `unit` (index absolu dans la suite aplatie), sur `total`.
        case printing(unit: Int, total: Int)
        /// En pause sur l'unité `unit` après un échec : `message` décrit l'erreur.
        case paused(unit: Int, total: Int, message: String)
        /// Tout a été traité (`printed` imprimées, `skipped` sautées).
        case done(printed: Int, skipped: Int)
    }

    /// Une unité à imprimer : à quel produit elle appartient, et son rang (1-based)
    /// au sein de ce produit (« 2/3 »).
    public struct Unit: Equatable {
        public let jobID: String
        public let copyIndex: Int   // 1-based, dans le produit
        public let jobCopies: Int   // quantité totale de ce produit
    }

    /// Suite aplatie des unités (une entrée par étiquette à sortir).
    private let units: [Unit]
    private(set) public var state: State = .idle
    /// Curseur : index de la prochaine unité à imprimer.
    private var cursor = 0
    private(set) public var printedCount = 0
    private(set) public var skippedCount = 0

    public init(jobs: [PrintQueueJob]) {
        var flattened: [Unit] = []
        for job in jobs {
            for copy in 1...job.quantity {
                flattened.append(Unit(jobID: job.id, copyIndex: copy, jobCopies: job.quantity))
            }
        }
        self.units = flattened
    }

    /// Nombre total d'étiquettes à sortir (toutes quantités confondues).
    public var total: Int { units.count }

    /// L'unité actuellement visée (en cours ou en pause), nil si idle/done.
    public var currentUnit: Unit? {
        switch state {
        case .printing(let unit, _), .paused(let unit, _, _):
            return unit < units.count ? units[unit] : nil
        case .idle, .done:
            return nil
        }
    }

    public var isActive: Bool {
        switch state {
        case .printing, .paused: return true
        case .idle, .done: return false
        }
    }

    /// Démarre la file. Transition vers `printing` sur la première unité, ou
    /// directement `done` si la file est vide.
    public mutating func start() {
        cursor = 0
        printedCount = 0
        skippedCount = 0
        advanceToPrintingOrDone()
    }

    /// L'unité courante a été imprimée avec succès : avance d'un cran.
    public mutating func markPrinted() {
        guard case .printing = state else { return }
        printedCount += 1
        cursor += 1
        advanceToPrintingOrDone()
    }

    /// L'impression de l'unité courante a échoué : met la file en pause sur cette
    /// même unité (le curseur ne bouge pas).
    public mutating func markFailed(message: String) {
        guard case .printing(let unit, let total) = state else { return }
        state = .paused(unit: unit, total: total, message: message)
    }

    /// Reprise après pause : réessayer l'unité qui a échoué (repart en `printing`
    /// sur la même unité).
    public mutating func retry() {
        guard case .paused(let unit, let total, _) = state else { return }
        state = .printing(unit: unit, total: total)
    }

    /// Reprise après pause : sauter l'unité en échec et continuer avec la suivante.
    public mutating func skipFailed() {
        guard case .paused = state else { return }
        skippedCount += 1
        cursor += 1
        advanceToPrintingOrDone()
    }

    /// Reprise après pause : annuler le reste de la file. Les étiquettes déjà
    /// sorties restent comptées ; celles non traitées ne sont pas sautées.
    public mutating func cancel() {
        guard case .paused = state else { return }
        state = .done(printed: printedCount, skipped: skippedCount)
    }

    /// Progression lisible pour l'UI (« 2/5 »), basée sur l'unité visée.
    public var progressText: String? {
        switch state {
        case .printing(let unit, let total), .paused(let unit, let total, _):
            return "\(unit + 1)/\(total)"
        case .idle, .done:
            return nil
        }
    }

    private mutating func advanceToPrintingOrDone() {
        if cursor < units.count {
            state = .printing(unit: cursor, total: units.count)
        } else {
            state = .done(printed: printedCount, skipped: skippedCount)
        }
    }
}
