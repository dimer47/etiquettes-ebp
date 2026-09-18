import Foundation

@MainActor
final class LabelHistoryStore: ObservableObject {
    @Published private(set) var entries: [PrintedLabel]
    private let defaults: UserDefaults
    private static let storageKey = "printedLabelHistory"
    private static let maximumEntries = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PrintedLabel].self, from: $0) } ?? []
    }

    func record(_ entry: PrintedLabel) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { entries.remove(at: index) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
