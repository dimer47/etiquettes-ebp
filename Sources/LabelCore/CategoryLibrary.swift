import Foundation

public enum CategoryLibrary {
    public static func adding(_ value: String, to categories: [String]) -> [String] {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !categories.contains(where: { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else { return categories }
        return (categories + [name]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
