import XCTest
@testable import LabelCore

final class PrintQueueTests: XCTestCase {

    // MARK: - Aplatissement et démarrage

    func testEmptyQueueGoesStraightToDone() {
        var machine = PrintQueueMachine(jobs: [])
        XCTAssertEqual(machine.state, .idle)
        machine.start()
        XCTAssertEqual(machine.state, .done(printed: 0, skipped: 0))
    }

    func testFlattensQuantitiesIntoUnits() {
        let machine = PrintQueueMachine(jobs: [
            PrintQueueJob(id: "A", quantity: 2),
            PrintQueueJob(id: "B", quantity: 3),
        ])
        XCTAssertEqual(machine.total, 5)
    }

    func testStartPointsAtFirstUnit() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 2)])
        machine.start()
        XCTAssertEqual(machine.state, .printing(unit: 0, total: 2))
        XCTAssertEqual(machine.currentUnit?.jobID, "A")
        XCTAssertEqual(machine.currentUnit?.copyIndex, 1)
        XCTAssertEqual(machine.progressText, "1/2")
    }

    // MARK: - Chemin nominal

    func testHappyPathPrintsEveryUnitInOrder() {
        var machine = PrintQueueMachine(jobs: [
            PrintQueueJob(id: "A", quantity: 2),
            PrintQueueJob(id: "B", quantity: 1),
        ])
        machine.start()

        XCTAssertEqual(machine.currentUnit?.jobID, "A")
        XCTAssertEqual(machine.currentUnit?.copyIndex, 1)
        machine.markPrinted()

        XCTAssertEqual(machine.currentUnit?.jobID, "A")
        XCTAssertEqual(machine.currentUnit?.copyIndex, 2)
        machine.markPrinted()

        XCTAssertEqual(machine.currentUnit?.jobID, "B")
        XCTAssertEqual(machine.progressText, "3/3")
        machine.markPrinted()

        XCTAssertEqual(machine.state, .done(printed: 3, skipped: 0))
        XCTAssertNil(machine.currentUnit)
        XCTAssertFalse(machine.isActive)
    }

    // MARK: - Pause / reprise sur erreur (le cœur de la feature)

    func testFailurePausesOnSameUnitWithoutAdvancing() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 3)])
        machine.start()
        machine.markPrinted()   // unité 0 OK → on vise l'unité 1

        XCTAssertEqual(machine.state, .printing(unit: 1, total: 3))
        machine.markFailed(message: "Rouleau vide")

        XCTAssertEqual(machine.state, .paused(unit: 1, total: 3, message: "Rouleau vide"))
        // Le curseur n'a pas bougé : l'unité en échec reste la prochaine.
        XCTAssertEqual(machine.currentUnit?.copyIndex, 2)
        XCTAssertEqual(machine.printedCount, 1)
    }

    func testRetryContinuesExactlyWhereItStopped() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 3)])
        machine.start()
        machine.markPrinted()                       // 1 OK
        machine.markFailed(message: "Bourrage")     // 2 échoue → pause

        machine.retry()
        XCTAssertEqual(machine.state, .printing(unit: 1, total: 3))  // reprend l'unité 2
        machine.markPrinted()                       // 2 OK (au 2e essai)
        XCTAssertEqual(machine.state, .printing(unit: 2, total: 3))  // enchaîne sur la 3
        machine.markPrinted()                       // 3 OK

        XCTAssertEqual(machine.state, .done(printed: 3, skipped: 0))
        // Rien n'a été réimprimé en double : exactement 3 impressions comptées.
        XCTAssertEqual(machine.printedCount, 3)
    }

    func testSkipFailedContinuesWithNextUnit() {
        var machine = PrintQueueMachine(jobs: [
            PrintQueueJob(id: "A", quantity: 1),
            PrintQueueJob(id: "B", quantity: 1),
            PrintQueueJob(id: "C", quantity: 1),
        ])
        machine.start()
        machine.markPrinted()                       // A OK
        machine.markFailed(message: "Hors tension") // B échoue → pause

        machine.skipFailed()
        XCTAssertEqual(machine.currentUnit?.jobID, "C")  // saute B, vise C
        machine.markPrinted()                            // C OK

        XCTAssertEqual(machine.state, .done(printed: 2, skipped: 1))
    }

    func testCancelFromPauseStopsTheRest() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 4)])
        machine.start()
        machine.markPrinted()                       // 1 OK
        machine.markFailed(message: "Déconnectée")  // 2 échoue → pause

        machine.cancel()
        XCTAssertEqual(machine.state, .done(printed: 1, skipped: 0))
        XCTAssertFalse(machine.isActive)
    }

    func testRetryThenFailAgainStaysPausedOnSameUnit() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 2)])
        machine.start()
        machine.markFailed(message: "err 1")
        machine.retry()
        machine.markFailed(message: "err 2")
        XCTAssertEqual(machine.state, .paused(unit: 0, total: 2, message: "err 2"))
        XCTAssertEqual(machine.printedCount, 0)
    }

    // MARK: - Garde-fous sur les transitions invalides

    func testMarkPrintedIgnoredWhilePaused() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 2)])
        machine.start()
        machine.markFailed(message: "x")
        machine.markPrinted()   // ignoré : on est en pause, pas en impression
        XCTAssertEqual(machine.state, .paused(unit: 0, total: 2, message: "x"))
    }

    func testRetryIgnoredWhenNotPaused() {
        var machine = PrintQueueMachine(jobs: [PrintQueueJob(id: "A", quantity: 1)])
        machine.start()
        machine.retry()   // ignoré : on n'est pas en pause
        XCTAssertEqual(machine.state, .printing(unit: 0, total: 1))
    }

    func testJobQuantityIsClampedToAtLeastOne() {
        let job = PrintQueueJob(id: "A", quantity: 0)
        XCTAssertEqual(job.quantity, 1)
    }
}
